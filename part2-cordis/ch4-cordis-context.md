# 第 4 章 Cordis 源码解析：Context 与反射层

Cordis 的源码被 vendored 在仓库 `vendor/cordis/src/` 下，共 9 个文件约 2700 行：

```
vendor/cordis/src/
├── context.ts    # Context：代理容器 + extend/isolate/intercept
├── service.ts    # Service 基类
├── fiber.ts      # Fiber：插件运行时生命周期
├── events.ts     # EventsService：五种派发模式
├── registry.ts   # RegistryService：插件注册表 + Inject
├── reflect.ts    # ReflectService：代理陷阱 + 服务解析
├── logger.ts     # LoggerService
├── utils.ts      # 符号、traceable、composeError 等工具
└── index.ts      # 导出
```

本章先拆 **Context 与反射层**——它们是 Cordis 一切魔法（`ctx.foo` 即服务）的物理基础。

## 4.1 Context：一个代理

`Context` 的类声明极其简短（`context.ts:42-146`）：真正的类只有构造器、`extend`、`isolate`、`intercept` 四个成员。但它不是一个普通对象——**每个 context 实例都是一个 Proxy**：

```ts
// context.ts:71-84
constructor() {
  this[symbols.isolate] = Object.create(null)
  this[symbols.intercept] = Object.create(null)
  const self = new Proxy<this>(this, ReflectService.handler)
  this.root = self
  this.baseUrl = undefined
  this.fiber = new Fiber(self, {}, Object.create(null), null, () => [])
  this.reflect = new ReflectService(self)
  this.registry = new RegistryService(self)
  this.events = new EventsService(self)
  this.logger = new LoggerService(self)
  this.fiber._disposables.clear()
  return self
}
```

注意：构造函数**返回了代理** `self`（而不是 `this`）。因此任何 `new Context()` / `ctx.extend()` 的结果，所有属性读取都会先经过 `ReflectService.handler` 的 `get` 陷阱。

`Context.is()` 用全局 symbol（`Symbol.for('cordis.is')`）做品牌检测，跨 realm、跨多份 cordis 拷贝都能识别 context（`context.ts:61-68`）。

### 两个内部状态表

每个 context 携带两张表：

- `[symbols.isolate]: Dict<symbol>`——**隔离映射**：服务名 → 作用域标签。查找某服务名时，在该标签内解析；
- `[symbols.intercept]: Dict`——**拦截映射**：服务名 → 合并进该服务每插件配置的 intercept 配置。

两者都是**原型链式**的（`Object.create(null)` 沿原型继承），这正是子 context "继承父作用域、覆盖局部条目"的机制。

## 4.2 三种子 context 原语

`extend(meta)` 创建子 context：以当前 context 为原型（`getTraceable(this, this)`），把 `meta` 的属性定义到子对象上（`context.ts:99-107`）。父 context 不被改动。它还能携带 `[symbols.shadow]`——影子 context，在服务解析时会被特殊对待（见 4.4）。

`isolate(name, label?)` 创建"独立服务作用域"：新 context 的隔离映射**原型继承**父映射，再把 `name` 指向一个新的（或传入的）标签 symbol（`context.ts:121-125`）。效果：

- 在返回的 context 之下，`name` 服务的读写解析到**新标签**；
- 同一个 `label` 传给两次 `isolate()` 会把它们的作用域**合并**——这正是 agent preset 里"provider 与消费者共享同一 isolate realm"的实现基础；
- 父作用域不受影响。

`intercept(name, config)` 类似：在拦截映射上沿原型新增一条 `name → config`（`context.ts:139-145`）。服务实例在解析配置时会沿原型链收集所有 intercept 条目（`Service[symbols.resolveConfig]`，`service.ts:86-102`）——离根越近的条目优先级越低，`base` 垫底、`head` 置顶，最终经 `Config.merge`（若声明）或浅 `Object.assign` 合并。

## 4.3 反射层：Proxy 陷阱

`ReflectService.handler`（`reflect.ts:135-206`）是 context 代理的陷阱集合。核心是 `get`：

```ts
get: (target, prop, ctx) => {
  if (isSpecialProperty(prop)) return Reflect.get(target, prop, ctx)   // 特殊键直通
  if (Reflect.has(target, prop)) return getTraceable(ctx, Reflect.get(target, prop, ctx))
  const error = new Error(`cannot get property "${prop}" without inject`)
  try {
    const def = target.reflect.props[prop]
    if (def?.type === 'accessor') return def.get.call(ctx, ctx[symbols.receiver], error)
    if (!ctx.fiber.runtime) return ctx.reflect.get(prop, false)
    return ctx.events.waterfall('internal/get', ctx, prop, error, () => { /* 服务解析 */ })
  } catch (e) { throw e === error ? enhanceError(e) : e }
}
```

解析顺序：

1. **特殊键直通**：symbol、保留字（`prototype`、`then`）、数字字符串、下划线开头——不经过服务解析（`isSpecialProperty`，`reflect.ts:86-91`）。这保证 `ctx.then` 等不会被服务劫持；
2. **自有/原型属性**：如 `ctx.fiber`、`ctx.reflect` 等真实属性，直接返回（并包上 traceable）；
3. **accessor 属性**：执行 `get` 钩子；
4. **服务解析**：走 `internal/get` waterfall（可被插件拦截！），最终在 fiber 的 store 链上查找实现（见下）。

`set` 陷阱对称：普通属性直通；accessor 走 `set` 钩子（可返回 `false` 拒绝写）；服务写入走 `internal/set` waterfall → `ctx.reflect.set()`。

`has` 陷阱保证 `'tools' in ctx` 对已声明属性返回 true。

### 服务解析的向上查找

`get` 陷阱中的核心逻辑（`reflect.ts:153-167`）：

```ts
const key = target[symbols.isolate][prop]
let fiber = (ctx[symbols.shadow] ?? ctx).fiber
while (true) {
  const impl = fiber.store?.[prop]
  if (impl) return getTraceable(ctx, impl.value)      // 当前 fiber 提供
  if (prop in fiber.inject) throw /* 需要的服务未激活 */
  if (!fiber.runtime) throw error                      // 到根了
  if (fiber.parent[symbols.isolate][prop] !== key) throw error  // 作用域变了
  fiber = fiber.parent.fiber                            // 向父 fiber 回溯
}
```

每个 fiber 的 `store` 是"本 fiber 提供的服务实现"快照；解析时先查自己，再沿 `parent.fiber` 链向上，直到根。**若某层父作用域的隔离标签与当前不同，立即停止**——这实现了 isolate 的"墙"。

`error` 对象携带调用栈，用于"cannot get property X without inject"这类经典报错——`enhanceError` 会把报错信息重写为清晰的提示（`reflect.ts:73-78`）。

## 4.4 服务注册：provide / get / set / accessor / mixin

`ReflectService` 维护两张表：

- `store: Dict<Impl, symbol>`——按**隔离标签**键控的实现表。`Impl = { name, value, fiber, check? }`（`reflect.ts:116-125`）：实现归属哪个 fiber、当前值、可选可用性谓词；
- `props: Dict<Property>`——已声明的上下文属性（`'service' | 'accessor'`）。

`ctx.provide(name, value, check?)`（`reflect.ts:277-304`）是服务的注册入口，同时也是 `Service` 基类构造器内部的调用点。它的实现是一枚 **fiber effect**：

```ts
provide(name, value, check?) {
  return this.ctx.fiber.effect(() => {
    this.props[name] = { type: 'service' }
    this.ctx.root[symbols.isolate][name] ??= Symbol(name)   // 根上建立默认标签
    const key = this.ctx[symbols.isolate][name]
    const impl = { name, value, fiber: this.ctx.fiber, check }
    if (this.store[key]) throw new Error(`service "${name}" has been registered ...`)
    this.store[key] = impl
    this.ctx.fiber.store![name] = impl
    if (this.ctx.fiber.state === FiberState.ACTIVE) this.notify([name])
    return async () => {                                    // 反注册
      delete this.store[key]
      const fibers = this.notify([name])
      await Promise.allSettled(fibers.map(fiber => fiber.await()))
      delete this.ctx.fiber.store![name]
    }
  }, `ctx.provide(${JSON.stringify(name)})`)
}
```

要点：

- 服务注册**本身就是副作用**：fiber 卸载自动反注册，依赖者被唤醒重新评估；
- 同名服务在同一隔离标签内**只能注册一次**，重复注册直接抛错——这是"无特权核心"的另一面：任何两枚插件提供同名服务都会在启动期暴露冲突；
- 反注册时先 `notify` 唤醒依赖者并**等待它们卸载完成**（`await fiber.await()`），再删除自己的 store 条目——保证"先依赖后自己"的清理顺序。

`notify(names, filter?)`（`reflect.ts:314-336`）是依赖图更新的发动机：遍历注册表中所有 fiber，对每个声明了 `inject` 相关服务的 fiber 重新 `_checkImpl` + `_refresh`，随后派发 `internal/service` 事件（带作用域过滤）。服务出现/消失 → 依赖者被重新装载，这是 Cordis 自动依赖管理的核心循环。

`ctx.get(name, strict?)`（`reflect.ts:233-235`）是**非注入**的读取：按当前隔离标签查 store，`strict=true`（默认）时要求提供者 fiber 处于 ACTIVE。这正是动态插件开发里 `ctx.get('service')` 的语义——可选服务，可能 `undefined`。

`ctx.set(name, value)` 只能由提供该服务的 fiber 覆写（`reflect.ts:254-265`），跨 fiber 写会抛错——服务归属权是硬约束。

`ctx.accessor(name, {get, set})` 注册计算属性（`reflect.ts:345-353`），也是 effect。

`ctx.mixin(source, keys)` 把服务的成员**直接暴露到 ctx 上**（`reflect.ts:364-390`）：`ctx.on` 其实是 `ctx.events.on`，`ctx.plugin` 是 `ctx.registry.plugin`，`ctx.effect` 是 `ctx.fiber.effect`……四个核心 mixin 在 `ReflectService` 构造器里建立（`reflect.ts:219-223`）：

```ts
this.mixin('reflect', ['get', 'set', 'provide', 'accessor', 'mixin'])
this.mixin('fiber', ['runtime', 'effect'])
this.mixin('registry', ['inject', 'plugin'])
this.mixin('events', ['on', 'once', 'parallel', 'emit', 'serial', 'bail', 'waterfall'])
```

mixin 生成的 accessor 会把方法绑定到服务实例上，并保留调用者的 context 属性（`withProps`）——所以 `ctx.on()` 里的 `this` 仍然是 ctx。

## 4.5 traceable 与错误增强

`getTraceable(ctx, value)`（`utils.ts`）把服务值包成 proxy：访问其属性时若命中 context 追踪器（`symbols.tracker`），会改写 `this` 指向正确的 context。`ReflectService.bind()` 类似地包装回调，使事件监听器里的 `this` 与参数自动"追踪"到所属 context。这是 dsh 里 `Scoped` 派发、`internal/service` 过滤等高级特性的基础，也是 debug 时"为什么这个 `this` 是 context"的答案。

`enhanceError`（`reflect.ts:73-78`）把代理陷阱中抛出的错误栈首行改写为清晰的 `Error: cannot get property "x" without inject`——这是插件作者最常遇到的那条报错的来源。

## 4.6 小结

- context = Proxy；属性读取即服务解析；
- 解析顺序：特殊键 → 真实属性 → accessor → `internal/get` waterfall → fiber store 链向上查找；
- isolate 用"标签墙"隔离同名服务；intercept 沿原型链合并配置；extend 产生子 context；
- 服务注册是 fiber effect，重复注册同标签同名会抛错；notify 驱动依赖者重载；
- mixin 让核心服务的方法直接出现在 ctx 上。

下一章看 `Service` 基类与 `Fiber` 生命周期——插件的"运行时"。
