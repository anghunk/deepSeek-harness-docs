# 第 6 章 Cordis 源码解析：事件系统与派发模式

事件是 Cordis 插件间通信的主干，也是 dsh 全部扩展点的形态。`EventsService`（`events.ts:131-319`）只有约 190 行，却支撑了五种派发模式、context 过滤、fiber 自动清理与内部事件钩子。

## 6.1 五种派发模式

```ts
export type DispatchMode = 'emit' | 'parallel' | 'serial' | 'bail' | 'waterfall'
```

| 模式 | 是否等待 | 顺序 | 返回值 | 语义 |
| --- | --- | --- | --- | --- |
| `emit` | 否 | 注册序 | 无 | 观察者广播，同步触发不等待 |
| `parallel` | 是 | 并行 | 无（聚合错误） | 扇出并等待全部 settle |
| `serial` | 是 | 注册序 | 首个 bail 值 | 依次 await，遇到 bail 值提前停 |
| `bail` | 否 | 注册序 | 首个 bail 值 | 同步版 serial |
| `waterfall` | 否（取决于 next） | 注册序 | 最外层监听者的返回值 | 洋葱中间件 |

### emit：观察

```ts
emit(...args) {
  this.dispatch('emit', args).map(cb => cb(...args))
}
```

同步触发所有匹配监听者，忽略返回值，不等待 Promise。适合"事实通知"：`session/event`、`agent/status` 等。

### parallel：扇出并等待

```ts
async parallel(...args) {
  const results = await Promise.allSettled(this.dispatch('emit', args).map(async cb => cb(...args)))
  const errors = results.filter(r => r.status === 'rejected')
  if (errors.length) throw new AggregateError(errors.map(e => e.reason))
}
```

所有监听者并发执行，全部 settle 后返回；任何失败聚合为 `AggregateError` 抛出。适合"必须全部完成"的检查点——dsh 的 `session/flush` 持久化屏障就是 parallel。

### serial / bail：短路决策

```ts
async serial(...args) {
  for (const cb of this.dispatch('serial', args)) {
    const result = await cb(...args)
    if (isBailed(result)) return result
  }
}
```

`isBailed(value)` 定义"bail 值"：**非 null、非 false、非 undefined** 的任何值（`events.ts:13-15`）。`serial` 依次 await 每个监听者，第一个返回 bail 值的就短路返回。`bail` 是同步版本。适合"第一个说了算"的策略链，例如权限检查。

### waterfall：洋葱中间件

```ts
waterfall(...args) {
  const cbs = this.dispatch('waterfall', args)
  const inner = args.pop()          // 最后一个参数是内置行为 next
  const next = () => {
    const cb = cbs.shift() ?? inner // 依次取监听者，取尽后落到内置行为
    return cb(...args)
  }
  args.push(next)
  return next()
}
```

waterfall 是**围绕中间件**（around-middleware）：监听者收到 `(...args, next)`，调用 `next()` 委派给链上的下一个（最后是内置行为），**不调用 `next()` 即否决**（短路）；值通过 `next()` 的返回值传播，监听者可以包裹或整体替换结果。dsh 的 `agent/pre-step`、`tools/pre-execute`、`llm/stream` 等都是 waterfall——插件可以"改写输入、包裹输出、或者一票否决"。

## 6.2 dispatch：过滤与绑定

所有派发都经过 `dispatch(type, args)`（`events.ts:165-175`）：

```ts
dispatch(type, args) {
  const thisArg = typeof args[0] === 'object' || typeof args[0] === 'function' ? args.shift() : null
  const name = args.shift()
  if (!name.startsWith('internal/')) this.emit('internal/dispatch', type, name, args, thisArg)
  const filter = thisArg?.[Context.filter]
  return (this._hooks[name] || [])
    .filter(hook => hook.global || !filter || filter.call(thisArg, hook.ctx))
    .map(hook => hook.callback.bind(thisArg))
}
```

机制：

1. **可选 this 参数**：第一个参数若是对象/函数，视为 dispatch 的 `this`（用于过滤与回调绑定）；
2. **内部事件诊断**：非 `internal/` 前缀的事件先派发 `internal/dispatch`（可用于监控/日志）；
3. **context 过滤**：`thisArg[Context.filter]` 是过滤函数；监听者带 `global: true` 时不过滤。dsh 的 **scope 过滤**（`Scoped` 事件，agent 作用域）正是通过给 dispatch 传入携带 `[Context.filter]` 的载体对象实现的——这就是 `@dshScopeScan` 事件的底层机制；
4. 回调全部 `bind(thisArg)`。

## 6.3 监听注册与自动清理

`on(name, listener, options)`（`events.ts:288-302`）：

```ts
on(name, listener, options?) {
  if (typeof options !== 'object') options = { prepend: options }
  this.ctx.fiber.assertActive()
  listener = this.ctx.reflect.bind(listener)          // 追踪包装
  const result = this.bail(this.ctx, 'internal/listener', name, listener, options)
  if (result) return result                            // 内部钩子可接管注册
  const hooks = this._hooks[name] ||= []
  return this.register(`ctx.on(${JSON.stringify(name)})`, hooks, listener, options)
}
```

- 监听器经 `reflect.bind` 包装（`this` 与参数自动追踪到所属 context）；
- `internal/listener` **bail 事件**允许内部机制接管注册（例如 `internal/update` 的 fiber 内钩子存储，`events.ts:140-155`）；
- `register`（`events.ts:254-260`）把监听器作为 **fiber effect** 存储——**fiber 卸载时监听器自动移除**，这正是"插件卸载不留痕迹"的保障；
- `options.prepend` 控制插入位置；`options.global` 跳过 context 过滤；
- `once()` 用包装函数实现一次性（`events.ts:312-318`）。

## 6.4 内部事件

`Events` 接口（`events.ts:329-352`）声明了框架内建事件，全部以 `internal/` 前缀区分：

| 事件 | 模式 | 语义 |
| --- | --- | --- |
| `internal/plugin` | emit | fiber 创建/卸载通知 |
| `internal/status` | emit | fiber 状态迁移（带旧状态） |
| `internal/config` | waterfall | 解析插件配置前拦截（fiber 为 this） |
| `internal/service` | emit | 服务绑定/解绑通知（带作用域过滤） |
| `internal/update` | waterfall | 配置更新被应用前（`next()` 可否决） |
| `internal/get` / `internal/set` | waterfall | 通过 context 代理读写服务时拦截 |
| `internal/listener` | bail | 监听器注册接管 |
| `internal/dispatch` | emit | 非内部事件派发前诊断 |

这些内部事件把框架自身的机制（依赖解析、配置更新、监听注册）也变成可拦截的扩展点——dsh 的 HMR、配置持久化、scope 过滤都建立在它们之上。插件作者一般不需要直接使用它们，但理解它们有助于读懂 dsh 的深层代码。

## 6.5 类型化事件：声明合并

Cordis 的事件是**类型化**的：服务包通过 declaration merging 向 `Events` 接口添加成员，监听/派发都有完整类型检查。dsh 在此基础上约定：

- 每个事件声明 `@mode`（emit/parallel/serial/bail/waterfall），生成器 `gen-cordis-catalog.ts` 会**校验声明与派发现场一致**；
- 事件按领域组织：`session/*`、`agent/*`、`tools/*`、`fs/*` 等；
- scope 事件带 `Scoped<T>` 载体与 `@dshScopeScan` 标记，表示按 agent 作用域过滤派发。

dsh 的 `docs/event-producer-consumer.md` 是完整的事件生产者/消费者目录，由脚本生成、随源码同步。

## 6.6 小结

- 五种派发模式覆盖观察/扇出/决策/中间件四类需求；
- dispatch 统一处理 this 绑定与 context 过滤（scope 过滤的地基）；
- 监听器是 fiber effect：卸载自动移除；
- `internal/*` 事件把框架机制本身变成扩展点；
- 类型化事件 + `@mode` 声明让"事件契约"可被机器校验。

下一章：插件注册表——`ctx.plugin()` 如何把一枚插件变成一棵 fiber 树。
