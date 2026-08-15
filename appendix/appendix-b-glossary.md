# 附录 B 术语表

## 框架层

| 术语 | 释义 |
| --- | --- |
| **Cordis** | dsh 底层的插件框架（vendored 于 `vendor/cordis`）：服务、事件、可逆副作用 |
| **Context（ctx）** | 服务的仓库；一个代理对象，属性读取即服务解析 |
| **Service** | 挂到 `ctx.<key>` 上的能力；构造即注册、fiber 卸载即消失 |
| **Plugin** | 函数/类/对象三种形态的插件入口；`apply(ctx, config)` 为共同执行体 |
| **Fiber** | 一枚插件的一次装载；PENDING/LOADING/ACTIVE/FAILED/UNLOADING/DISPOSED 状态机 |
| **inject** | 插件声明的硬依赖；依赖就绪才装载，消失即卸载 |
| **effect** | 可逆副作用容器；卸载时逆序清理 disposer |
| **isolate** | 服务隔离作用域：同标签内提供独立实现，标签外不可见 |
| **intercept** | 服务配置拦截：子 context 的插件看到合并后的配置 |
| **emit / parallel / serial / bail / waterfall** | 五种事件派发模式：观察 / 扇出等待 / 串行决策 / 同步决策 / 洋葱中间件 |
| **waterfall next()** | 中间件委派；不调用 next() 即否决 |

## 运行层

| 术语 | 释义 |
| --- | --- |
| **Profile（配置档）** | 命名组合：bundles 列表 + 用户 patch；`web`/`headless` 为内置模板 |
| **Bundle（捆绑包）** | 配置行 + 代码的分发格式；`dsh-base`/`dsh-web-app`/`dsh-headless` 三种内置 |
| **Patch（补丁）** | 按 id 整行替换或 insert 新行的组合修改 |
| **Host / Client** | Node 进程侧 / 浏览器侧两棵 Cordis 树 |
| **agent preset** | 单个会话的能力组合（`~/.dsh/.agent-presets/<id>/`） |
| **isolate realm** | preset 内一组行共享的隔离服务作用域（`cordis:group`） |
| **seam（能力接缝）** | 定义 + 提供者 + 消费者三件套的可替换能力 |

## 会话与 Agent

| 术语 | 释义 |
| --- | --- |
| **Session（会话）** | 追加型 `SessionEvent` 日志；模型历史的唯一派生源 |
| **SessionEvent** | 一条日志条目：`{type, seq, time, data}`，写入时深冻结 |
| **Surface** | 三种消息产生型事件的派生表面；`replace` 是压缩机制 |
| **deriveMessages()** | 从日志派生模型历史（缓存 + 冻结） |
| **turn / step** | turn = 零或多个 step；step = 一次模型调用 + 其工具 |
| **Agent** | 活代理句柄：session、inbox、status、cancel/send/steer/inject |
| **inbox** | 待办消息投影（next-turn / next-step 两条列表） |
| **steer / inject** | 转向（最近 step 边界消费）/ 注入上下文（不唤醒） |
| **AgentCancelCause** | 取消原因：user/parent/hook/disposed |
| **Scoped\<T\>** | 按 agent 作用域过滤派发的事件载体 |
| **initiator** | 进程内异步调用链的发起者归属 |

## 扩展机制

| 术语 | 释义 |
| --- | --- |
| **defineTool** | 类型化工具构造 DSL（schema + execute + render + present*） |
| **tools/pre-execute** | 执行前策略 waterfall（权限/审批/沙箱） |
| **presentationMeta** | 工具结果的可重放卡片数据（随 `tool/result` 持久化） |
| **Code Mode** | 以代码表达操作的执行模式；复用同一受保护管道 |
| **dynamic plugin** | 会话内创建/审批/运行/更新/回滚的插件 |
| **Package** | 动态插件的不可变代码版本（packageId） |
| **Inspect Provider** | 只读接口目录（Service/Event/Builtin/Slot/Theme/Tool） |
| **Slot** | 客户端 UI 注册位（single/list/keyed/chain） |
| **@Remote** | Host 服务方法暴露给 Client 的生成式契约 |
| **boot manifest（__DSH_BOOT__）** | 注入页面的客户端插件入口图 |
