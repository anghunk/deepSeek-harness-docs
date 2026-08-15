# 第 7 章 Cordis 源码解析：插件注册表

最后一章框架解析：`RegistryService`（`registry.ts:195-337`）——`ctx.plugin()` 与 `ctx.inject()` 的实现。

## 7.1 插件的三种形态

```ts
// registry.ts:92-133
export type Plugin<T> =
  | Plugin.Function<T>      // (ctx, config) => any  函数插件
  | Plugin.Constructor<T>   // new (ctx, config)     类插件
  | Plugin.Object<T>        // { apply(ctx, config) } 对象插件
```

三种形态共享 `Plugin.Base` 元数据：

```ts
interface Base {
  name?: string                        // 显示名（fiber 诊断、logger 名）
  Config?: StandardSchemaV1            // 配置校验器
  inject?: Inject                      // 依赖声明
  provide?: string | string[]          // 提供的服务名（loader 读取）
  intercept?: Dict<boolean>            // 消费哪些服务的 intercept 配置
}
```

`inject` 有两种写法（`registry.ts:19`）：

```ts
type Inject = (keyof M)[]                    // ['sessions', 'tools'] 只要服务
           | { [K in keyof M]?: M[K] }       // { sessions: {...} } 附带 intercept 配置
```

数组形式只声明依赖；对象形式为每个服务附带"拦截配置"——该插件装载时，这些配置会合并进对应服务的解析配置（经 `Service[symbols.resolveConfig]`，见第 5 章）。`Inject.resolve`（`registry.ts:71-89`）把数组/对象/类继承的元数据规范化为 `name → config|null` 映射，并支持原型链继承（`@Inject` 装饰器写在父类上，子类可见）。

### 对象插件的 apply

DSH 动态插件的标准形态 `{ apply(ctx) { ... } }` 就是 `Plugin.Object`。`registry.resolve`（`registry.ts:222-228`）把可应用对象解析为 `plugin.apply` 函数作为注册表身份键（identity key）——同一个 `apply` 函数即同一插件。

### `@Inject` 装饰器

`registry.ts:37-60`：类装饰器把 `inject` 元数据写到类的静态属性（沿原型链继承）；方法装饰器把方法调用延迟到依赖服务就绪后（`initHooks` 机制）——这是类插件里"方法级注入"的语法糖。

## 7.2 Runtime：注册表的共享记录

```ts
interface Runtime {
  name?: string
  fibers: DisposableList<Fiber>   // 该插件的所有活 fiber
  callback: Function              // 可执行入口（注册表身份键）
  Config?: StandardSchemaV1
}
```

**一个插件（callback）对应一个 Runtime 记录，但可以有多个 fiber**——每调用一次 `ctx.plugin()` 就在当前 context 下创建一个新 fiber，共享同一 Runtime。`registry.delete(plugin)` 会 dispose 该 Runtime 下所有 fiber 并移除记录（`registry.ts:258-267`）。

## 7.3 plugin()：创建 fiber

```ts
plugin(plugin, config?, getOuterStack = buildOuterStack()) {
  const callback = this.resolve(plugin)
  if (!callback) throw new Error('invalid plugin, expect function or object with an "apply" method, ...')
  this.ctx.fiber.assertActive()                     // 当前 fiber 必须存活
  let runtime = this._internal.get(callback)
  if (!runtime) {
    runtime = { name: plugin.name, callback, fibers: new DisposableList(), Config: plugin.Config }
    this._internal.set(callback, runtime)
  }
  const fiber = new Fiber(this.ctx, config, Inject.resolve(plugin.inject), runtime, getOuterStack)
  const wrapped = Object.create(fiber)              // fiber & PromiseLike
  wrapped.then = (onFulfilled, onRejected) => fiber.await().then(onFulfilled, onRejected)
  return wrapped
}
```

要点：

- **fiber 可 await**：返回的包装对象既是 fiber（`.state`、`.dispose()`…）又是 PromiseLike——`await ctx.plugin(SomePlugin)` 会等它装载完成（或拒绝于启动错误）。`ctx.registry.inject(deps, cb)` 只是 `{ inject, apply: cb }` 的语法糖（`registry.ts:300-302`）；
- **身份键是 callback**：同一函数对象装载两次 = 同一个 Runtime、两个 fiber；不同函数对象 = 不同插件；
- 装载位置 = **当前 context**：`ctx.plugin()` 的调用点决定了新插件在 context 树中的位置（继承作用域/拦截配置）。这就是"在 agent 的 `agentCtx` 上装载插件 = 只对该 agent 生效"的原理。

### fiber 的嵌套卸载

`Fiber` 构造器里（`fiber.ts:265-297`），子 fiber 的 dispose 被注册为**父 fiber 的 effect**（`parent.fiber.effect(...)`，label 为 `ctx.plugin()`）。因此父插件卸载时，其装载的所有子插件按逆序自动卸载——插件树随 context 树一起生长与回卷。`emitPluginDisposed` 在真正清理前通知观察者，然后 drain 所有 in-flight 转换（`while (this.inertia) await this.inertia`）。

## 7.4 装载顺序与依赖等待

`RegistryService` 本身不排序——**顺序由依赖表达**：

1. 插件声明 `inject: ['a']`；
2. fiber 创建后立即 `_checkImpl('a')`（查 store）+ `_refresh()`（算纪元）；
3. `a` 未提供 → 纪元 `INACTIVE` → fiber 停在 **PENDING**，不运行插件代码；
4. 某插件 `ctx.provide('a', ...)` → `notify(['a'])` → 该 fiber `_checkImpl` + `_refresh` → 纪元有效 → `_reload` → 插件开始装载；
5. `a` 的提供者卸载 → notify → 纪元 INACTIVE → 该 fiber `_unload`。

启动审计（app-boot 的 `assertEntriesActivated`，见第 8 章）会检查"settle 后仍有 PENDING fiber"并报告其缺少的服务名——这就是启动失败时报 `pending (waiting for services: xxx)` 的来源。

## 7.5 诊断：getEffects 与 internal/status

调试插件时最有用的两个入口：

- `fiber.getEffects()`（`fiber.ts:568-572`）：返回当前注册的全部带标签 effect 的元数据树（`EffectMeta { label, children }`）——可以回答"这个插件到底注册了哪些东西"；
- `internal/status` 事件：fiber 每次状态迁移都会派发，监听它可以看到装载/卸载的完整时序。

## 7.6 框架部分小结

到此，Cordis 的四块拼图齐了：

| 拼图 | 文件 | 核心机制 |
| --- | --- | --- |
| Context | context.ts | Proxy 容器；extend/isolate/intercept |
| 反射 | reflect.ts | 属性解析、provide/get/set/accessor/mixin、notify |
| Fiber | fiber.ts | 状态机、依赖纪元、effect、配置校验 |
| 事件 | events.ts | 五种派发模式、过滤、自动清理 |
| 注册表 | registry.ts | 三种插件形态、Runtime、fiber 创建 |

现在我们已经知道"插件树"如何构建。下一部分进入 dsh 本体：看一枚真实的 `dsh web` 进程如何从 `dsh` 命令走到一棵完整的插件树，以及树上的核心子系统各自实现什么。
