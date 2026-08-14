# 第 10 章 会话日志：事件溯源核心

`packages/core/session` 是 dsh 的心脏：**会话（Session）是追加型（append-only）的类型化事件日志**，是整个 Agent 交互历史的唯一事实源。模型看到的 LLM 消息历史**从日志派生**，从不单独存储；重放就是从同一批事件重新派生。

> Source: `packages/core/session/src/types.ts`

## 10.1 为什么是事件溯源

`docs/subsystems/session.md` 的定位：

> A `Session` is an **append-only log** of typed `SessionEvent`s — the single source of truth for an agent's whole interaction history. The LLM message history is *derived* from the log, never stored separately; replay is re-derivation from the same events.

事件溯源带来几个关键性质：

1. **可重建性**：任何请求都是日志的纯函数（request/header 事件记录了完整请求信封）；
2. **可重放性**：UI、遥测、fork、resume 全部派生自同一条流；
3. **不可变性**：事件在写入时深冻结，日志不可被改写；
4. **可扩展性**：插件通过声明合并向 `SessionEventMap` 添加事件类型，无需改动核心。

配套不变式（官方强调）：

> **Model-visible means logged.** Anything that reaches a model request must be reconstructable from the log, and a runtime invariant asserts it.

"模型可见即已记录"——任何进入模型请求的内容必须能从日志重建。因此，新增模型可见输入 = 新增会话事件类型（扩展 `SessionEventMap` 并从日志渲染），而不是在循环里临时拼接。

## 10.2 SessionEventMap：事件词汇表

`SessionEventMap`（`types.ts`）是会话事件的完整词汇表，**merge-extensible**（插件声明合并扩展，如 compaction 接缝添加 `compaction/start`/`summary`/`end`）。核心事件（`docs/subsystems/session.md` 的 type-equiv 块）：

| 事件 | 载荷 | 语义 |
| --- | --- | --- |
| `turn/start` | `{ turn }` | 打开 turn（在认领输入/跑 pre-step 之前） |
| `turn/end` | `{ turn, reason }` | 关闭 turn，reason ∈ `TurnEndReasonMap` |
| `step/start` / `step/end` | `{ turn, step }` | 一个 step 的边界（一次模型调用 + 其工具执行） |
| `user/message` | `UserMessage` | 用户角色消息：直接提示、`agent.inject()` 注入上下文、目标续跑轮 |
| `assistant/chunk` | `{ turn, step, chunk }` | 原始流式块——token 级重放保真 |
| `assistant/message` | `{ turn, step, message, usage? }` | 组装好的助手消息（派生历史用它），携带 token 用量 |
| `tool/call` | `{ turn, step, callId, name, arguments }` | 模型请求一次工具调用（arguments 是模型原始 JSON 字符串，**不解析**） |
| `tool/result` | `{ turn, step, message, error?, meta? }` | 工具完成的模型可见结果 + 可选内部失败标识 + 工具私有 meta |
| `todo/write` | `{ todos }` | 任务清单整体快照（仅日志 UI 状态，不进派生历史） |
| `request/header` | `{ header, reason }` | 下一个请求的完整信封（配置+系统提示词+工具 schema） |
| `request/context` | `RequestContext` | 路由元数据（provider/model/contextWindow） |
| `session/end-seed` | — | 种子（resume/fork/replay）结束边界 |

**只记事实，不记中间态**：turn/step 边界、chunk、usage 都是"事实"；`request/header` 以全量快照记录（latest wins 重建）；`todo/write` 也是全量快照。而 `assistant/chunk` **必须**保留——`seq` 连续性是持久化契约，chunk 不能被过滤掉。

## 10.3 SessionEvent：日志条目

```ts
// types.ts（docs/subsystems/session.md type-equiv）
type SessionEvent<T extends SessionEventType = SessionEventType> = {
  [K in SessionEventType]: {
    type: K
    seq: number          // 单调序号，seq = log.length
    time: number         // epoch ms
    data: SessionEventMap[K]
    ignorable?: true     // 可安全跳过的纯信息记录
  } & (K extends SurfaceEventType ? {
    sourceEventSeqs?: number[]   // 引用的更早事件 seq
    surfaceOp?: SurfaceOp        // 'append' | { op: 'replace', start, end }
  } : object)
}[T]
```

设计要点：

- **真判别联合**：按 `type` 判别（而非独立的 type/data 联合），`switch (event.type)` 自动收窄 `event.data`；
- **ignorable 标记**：缺省 = 必需。读者遇到无法识别且无标记的事件**必须拒绝重建**，而不是静默丢弃——"忘记标记宁可过度拒绝，也不可静默续用一个被掏空的会话"；
- **Surface 元数据**：只有三种消息产生型事件（`SurfaceEventType = 'user/message' | 'assistant/message' | 'tool/result'`）可以携带 `surfaceOp` 与 `sourceEventSeqs`——编译器在 `Session.append` 调用点强制这一约束。

## 10.4 Surface：派生历史的唯一入口

三种消息产生型事件构成**有序表面（surface）**。`SurfaceOp`：

- `'append'`：正常追加到尾部；
- `{ op: 'replace', start, end }`：用本事件**替换** `start..end` 范围内的表面节点（`start === end` 单节点替换），被遮蔽的节点必须全部出现在 `sourceEventSeqs` 中——这是 **compaction（上下文压缩）** 的机制：压缩后一个摘要节点替换一批旧消息，派生历史立即反映压缩。

`Session.surface` 是活的只读投影：`nodes`（模型可见顺序的表面事件 seq 列表）+ `replaceGeneration`（位置替换的单调计数，增量消费者据此区分"纯尾部增长"与"重写"）。

**派生规则**（`deriveEventMessage`）：

- `user/message` → 用户消息（content 原样）；
- `assistant/message` → 助手消息；**空 content 的 assistant/message 被跳过**（max-tokens 截断仍记录 usage/provider/model，但不进模型转录）；
- `tool/result` → 携带 `tool-result` 块的用户消息；
- `assistant/chunk` → 派生时**跳过**（组装后的 message 才是权威）。

## 10.5 Session 公开 API

```ts
declare class Session {
  static create(id, seed?, header?)          // 分离式创建（replay/fork）
  static fromRestore(id, seed, header)       // 持久化恢复
  get surface(): SessionSurface
  get events(): readonly SessionEvent[]      // 深冻结快照
  get seq(): number                          // 下一个 seq = 日志长度
  append(type, data, opts?): SessionEvent    // 追加（热路径同步，无 I/O）
  deriveMessages(): Message[]                // 派生模型历史（缓存 + 冻结）
  requestHeader(): EpochHeader | undefined   // 折叠后的请求信封
  requestContext(): RequestContext | undefined
}
```

### append 的防御

`Session.append`（`packages/core/session/src/session.ts`）是全书防御性最强的函数之一：

- **无损 JSON 校验**：`data` 必须可无损 JSON 序列化（拒绝 BigInt、函数、symbol、undefined、负零、非有限数、循环引用、稀疏数组、Map/Set/Date/类实例……）——`isJsonValue` 在写入时校验，坏事件在源头被拒，持久化后端永远只见到合法事件；
- **单遍读写**：一次递归遍历同时完成"读、校验、拷贝"（防止有状态 getter 给校验一个值、给存储另一个值）；
- **表面契约校验**：marker 形态与资格、source 引用唯一、位置替换合法、遮蔽覆盖完整；
- **深冻结**：事件及嵌套数据在接纳时冻结，类型转换也无法改写持久历史；
- **重入拒绝**：append 接受/发布边界未闭合时再次 append 会拒绝。

### 持久化接缝

`Session` 本身**不实现持久化**——持久化是插件：订阅 `session/event` 事件、在 `session/flush`（parallel 检查点）排水。`ctx.sessions.flush(session)` 是唯一的 flush 入口（store 拥有 carrier，`docs/subsystems/session.md`）。JSONL 与 SQLite 后端见 `docs/subsystems/persistence.md`；崩溃恢复会合成 `{ kind: 'interrupted' }` 的 `turn/end`（循环本身从不发出该 reason）。

## 10.6 SessionStore：ctx.sessions

`SessionStore`（`packages/core/session/src/index.ts`）管理活会话：

| 方法 | 语义 |
| --- | --- |
| `create(id?, opts?)` | 创建并发布活会话（seed 事件 = replay/fork） |
| `prepare / enter / announce` | 分阶段生命周期：先构建（不进 store）→ 安装发布钩子并入库 → 派发 `session/created`（同步 throw 可否决并回滚）。`create` 是三步的便捷封装；需要"会话与循环按序拆卸"的调用方（agent factory）用三步版 |
| `get / list` | 查询 |
| `fork(source, boundary?, childSessionId?)` | 分叉：选 source 事件前缀（含 boundary seq，默认到当前末尾），要求前缀结束于 turn 之间（不得切开打开的 turn），深克隆种子事件 + 子会话元数据（parentSession、seedLength、继承 cwd） |
| `flush(session)` | 持久化检查点 |

## 10.7 会话事件：session/* 域

| 事件 | 模式 | 语义 |
| --- | --- | --- |
| `session/created` | emit | 创建公告；同步 throw 否决并回滚 |
| `session/disposed` | emit | 离开 store（含发布回滚）；只发一次 |
| `session/event` | emit | **提交后**的追加流（fire-and-forget，监听者快照在入队前解析、回调在入队后执行） |
| `session/flush` | parallel | 持久化检查点 |

四个事件都是 scope-filtered（`Scoped<Session>`）：agent 作用域监听者只收到经该 agent context 进入的会话事件——UI 订阅某个 agent 会话流的底层机制。

## 10.8 turn 结束原因

`TurnEndReasonMap`（可扩展联合）：

```ts
type TurnEndReasonMap = {
  completed: { kind: 'completed' }
  aborted: { kind: 'aborted'; reason: TurnEndCancelCause }
  blocked: { kind: 'blocked' }
  error: { kind: 'error'; error: LlmFailure }
  'max-tokens': { kind: 'max-tokens' }
  interrupted: { kind: 'interrupted' }   // 仅崩溃恢复合成
}
```

`max-tokens` 是**粘滞**的：turn 内任何 step 触顶，整个 turn 记 `max-tokens` 而非 `completed`——消费者能区分"干净停止"与"被截断"。取消与错误保持独立结局。

## 10.9 小结

- 会话 = 追加型事件日志；模型历史从日志派生（surface），"模型可见即已记录"；
- `SessionEventMap` 可声明合并扩展；事件写入时深冻结 + 无损 JSON 校验；
- surface 的 `replace` 是压缩机制；`replaceGeneration` 供增量消费者区分增长与重写；
- 持久化是插件接缝（`session/event` + `session/flush`）；
- `SessionStore` 的 prepare/enter/announce 分阶段生命周期支持有序拆卸与可否决发布。

下一章：Agent 循环——turn/step 状态机的实现。
