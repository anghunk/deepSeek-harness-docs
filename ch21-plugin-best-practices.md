# 第 21 章 最佳实践与调试

## 21.1 设计原则

### 就近原则（Placement）

"新行为放哪里"的第一问是**数据与能力在哪个平面**：

1. 数据在 Host（文件、进程、会话）→ Host 处理，需要展示时经最小 JSON 过桥；
2. 数据已在 Slot props（会话快照、工作区列表）→ 直接用 props，不加 RPC；
3. 只改自己组件的样式 → `styles.insert` + `--dsw-*` 变量；只有全局品牌才覆盖主题 token；
4. 只差一个小入口 → 找最窄的 Slot（`sidebar.footer.action`、`tool.view.cordis`），不要替换整个 sidebar/root。

### 事件优先于硬编码

- 拦截与策略用事件（waterfall/serial），直接能力调用用服务方法；
- 观察用 `emit`/`parallel`，决策用 `bail`/`serial`，包裹用 `waterfall`；
- **给事件选对域**：持久事实 → `SessionEventMap`（可重建）；在途观察 → `agent/*`；接缝策略 → `tools/*`/`fs/*`。

### 模型可见即已记录

任何要进模型的内容：

- 用 `agent.inject()`（持久、不唤醒）或 `user/message` 的插件 source；
- 不要绕过日志直接改消息——循环从日志重建请求，绕过即丢失；
- 新模型可见输入 = 新会话事件类型（声明合并 `SessionEventMap` + 从日志渲染）。

### 可逆性与所有权

- 每个注册都从 `ctx.effect()`/`ctx.on()`/服务返回的 disposer 获得清理；
- 清理顺序重要的相关工作放**同一个** effect（generator 逐个 yield）；
- 持有外部订阅时用 `ctx.effect(() => subscribe(...))` 并确保 subscribe 返回 disposer；
- 不要假设卸载会自动清理任意第三方回调。

## 21.2 数据纪律

### 内部活数据不可序列化

`Session`、`Agent`、`ToolExecution`、Slot props 等是**内部活数据**，不是普通 JSON：

- 禁止 `JSON.stringify`/`structuredClone` 整个对象或递归枚举；
- 只读任务需要的叶子字段（字符串/数字/布尔），构造**最小自有数据对象**；
- RPC 参数与返回值必须无损 JSON（禁函数/React 元素/类实例/服务实例）；无数据返回 `null`。

### 深冻结是保护不是负担

会话事件、派生消息、请求配置在写入时冻结——不要试图改写它们；需要"新值"就追加新事件（`replace` 表面操作由框架执行）。

## 21.3 性能要点

1. **热路径零分配**：事件载波（scope carrier）构造一次复用；`agent/inbox/spliced` 等先落盘再广播，观察者读到的列表仍是切除前视图；
2. **增量折叠**：`deriveMessages`/`requestHeader` 每节点只投影一次（缓存），增量消费用 `replaceGeneration` 区分尾部增长与重写；
3. **读不建层**：scope 的 `ScopedLayers` 读操作不创建 exact-scope 层，整层空时回收；
4. **批量通知**：Slot `subscribe` 变更按微任务批量（同 tick N 个变更 = 一个通知）；
5. **避免重复注入**：runtime-context 投影只在内容真正变化时才注入新快照（diffing），空时注入 CLEARED 标记。

## 21.4 防御性编写

- **fail loud**：配置坏、依赖缺、契约违反——尽早抛清晰错误，绝不静默降级（dsh 的启动审计、append 校验、sweep 补偿都是这个哲学的体现）；
- **不信任上游输入**：模型生成的工具参数、插件可控的字符串（boot 清单里的 `<` 转义）、客户端 payload——按外部输入处理；
- **取消要响应**：`exec.signal`/`task.signal` 触发时取消在途工作；发布到 jobs 的任务生命周期归任务控制器；
- **呈现器必须纯**：`presentCall`/`presentResult` 在实时与重放两条路径运行——无 I/O、无会话读取、无时钟；防重放崩溃用 `defineTool` 的软校验（畸形参数返回 undefined 而非 throw）。

## 21.5 调试工具链

| 工具 | 用途 |
| --- | --- |
| `cordis_inspect_self(pluginId, packageId)` | 读 Package 源码与运行诊断（消息 + 栈） |
| `fiber.getEffects()` | 看插件注册了哪些带标签的 effect（诊断树） |
| `internal/status` 事件 | 观察 fiber 状态迁移时序 |
| `ctx.logger(name)` | 命名日志（`dsh` 前缀、按服务过滤） |
| `dsh --profile web --dump-config` | 看组合后的配置树（哪些行被谁 patch） |
| `docs/subsystems/*` 的 cordis-catalog | 精确服务/事件签名（生成自源码） |
| `docs/event-producer-consumer.md` | 事件生产者/消费者目录 |
| `docs/tool-catalog.md` / `docs/persistence-catalog.md` | 工具与持久化事件目录 |

### 常见启动失败速查

| 症状 | 原因与位置 |
| --- | --- |
| `plugin(s) failed to load: x` | 模块解析失败（`assertEntriesLoaded`） |
| `N entries did not activate` + `pending (waiting for services: ...)` | 依赖服务从未出现（`assertEntriesActivated`） |
| `dsh: fatal load failure: ...` | 启动后未捕获 rejection（`installFailLoud`） |
| `service "x" has been registered at <fiber>` | 同作用域重复提供服务 |
| `cannot get property "x" without inject` | 未声明 inject 读取 ctx 属性 |

## 21.6 测试

- 工具/服务：vitest 单元测试，参照各包 `tests/`（mock adapter、contract-regression 等模式）；
- 插件：用 `packages/test-support` 的工具（llm-mock-server 等）做集成测试；
- e2e：真实 API 测试需 `DEEPSEEK_API_KEY`（未设置自跳过）；
- 快照：`DSH_SNAPSHOT=record|refresh|replay`；
- Web：`pnpm run test:web`（基于构建产物）。

## 21.7 发布与兼容

- 项目处于 developer preview：**破坏性变更是预期内**，升级前阅读 CHANGELOG 与文档；
- 插件包建议加 `dsh-plugin` topic 提高可发现性；
- 包间依赖用 `peerDependencies` 表达（与仓库约定一致）；
- 若修改了官方文档化的公开 API，同步更新 README/JSDoc（仓库有 verify 门禁）。

## 21.8 小结

- 就近原则：数据在哪、能力在哪、入口多窄，三层就近；
- 事件按域选择；模型可见即已记录；
- 活数据最小化、JSON 边界干净；
- fail loud、信任边界清晰、取消响应、呈现纯函数；
- 用好 inspect/诊断/目录三件套，启动失败速查表对号入座。

至此本书正文结束。附录提供命令速查、术语表与参考资源。
