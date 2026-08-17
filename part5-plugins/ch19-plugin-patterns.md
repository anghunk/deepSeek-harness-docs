# 第 19 章 插件开发实战模式

本章给出一组经过验证的实战模式，覆盖 dsh 插件开发的主要场景：工具、事件、服务、UI、主题、定时器、Host↔Client RPC、后台作业。每个模式都来自官方 cookbook、示例仓库或生产包（`dsh-tool-bash`、`dsh-tool-fs`、`dsh-market` 插件商店等）。

## 19.1 模式一：模型可见工具（Tool）

第 18 章的 `defineTool` 示例就是完整模式。生产级工具还需注意（官方 cookbook 的规则）：

1. **参数自动校验**：`defineTool` 在 `execute` 前按 `ParameterSchemaSpec` 校验模型生成的 arguments；DSL 表达不了的约束（非空字符串、正数、跨字段规则）自行检查；
2. **执行身份不可变**：`exec` 携带 `{ token, callId, agent, signal }`，参数在策略开始前冻结；`args` 是只读输入；`signal` 必须响应（取消在途工作）；
3. **返回单一规范 JSON 值**：`output.schema` 声明返回值，`execute` 只返回推断值；不要返回 content block、不要让调用方解析散文提取 id；
4. **抛错 = isError**：注册表捕获 throw 与校验失败，在观察者运行前包含；
5. **UI 卡片独立于模型结果**：`output.render` 拥有模型可见散文；`presentCall`/`presentResult` 拥有可重放的 UI 卡片（generic/terminal/diff/search/web 五种 kind）；
6. **呈现器必须纯**：它们会在实时流与日志重放两条路径运行——无 I/O、无会话状态读取、无时钟/随机；`presentationMeta` 投影可重放的卡片数据（如 write/edit 的 hunks）随 `tool/result` 持久化；
7. **后台化**：长任务走 `ctx.jobs.start({ kind, label, owner: exec.agent, run })`，返回 `{ kind: 'background', jobId }` 类型化句柄；发布后任务生命周期归 `job_kill`/所有者，不再归 `exec.signal`。

> 生产级三件套参考：`packages/shell/tool-bash`（terminal 卡片 + 流式 + 后台作业）与 `packages/fs/tool-fs`（diff 卡片 + presentationMeta）。

## 19.2 模式二：事件策略插件（权限门）

"部署策略不写进工具"——用 `tools/*` 事件实现可插拔策略（官方 extension-cookbook 的 permission-gate 示例）：

```ts
export function apply(ctx: Context) {
  // 扩展性策略：允许/拒绝/询问
  ctx.on('tools/pre-execute', async (payload, next) => {
    const verdict = await policy.check(payload.name, payload.arguments)
    if (verdict === 'allow') return next()
    if (verdict === 'deny') return { denied: true, reason: verdict.reason }
    return askHuman(payload)   // 审批：挂起等待人工批准/拒绝
  })

  // 最终单调拒绝：后续监听者无法撤销
  ctx.tools.guard((payload) => isDenied(payload.name))
}
```

监听 `tools/execute`（包裹 deadline/重试/指标）、`tools/post-execute`（替换呈现或返回值、附加模型可见上下文）、`tools/result`（观察不可变规范化结果）。

## 19.3 模式三：提供服务 + 事件（能力接缝三件套）

新增一个能力 = 定义 + 提供者 + 消费者（第 3 章）。以"远程沙箱"为例：

```ts
// 定义（接口）+ 提供者（实现）在同一包或分离包
export const provide = 'shell'
export function apply(ctx: Context) {
  ctx.provide('shell', {
    async execute(command, opts) { ... },   // 实现细节自由
  })
  // 可选：把实现也接到现有接缝上（第 15 章）
}

// 消费者：模型工具经 ctx.shell 执行
export function apply(ctx: Context) {
  const shell = ctx.get('shell')
  if (shell === undefined) return
  ctx.tools.register(defineTool({
    name: 'bash',
    // ...
    async execute(args, exec) {
      return shell.execute(args.command, { signal: exec.signal })
    },
  }))
}
```

换 Provider 换整个产品：`dsh-shell-local` 换成 `dsh-shell-remote`，Bash/PTY/LSP 全部随之迁移。

## 19.4 模式四：客户端 UI（Slot + 主题）

浏览器端插件在 `package.json` 声明 `dsh.client`，客户端代码注册 Slot：

```ts
// client 代码（纯 JS，无 TS/JSX 转换）
return {
  apply(ctx) {
    const slots = ctx.get('slots')
    if (slots === undefined) return
    slots.inject('settings.section', () => slots.register(
      { name: 'settings.section', id: 'my-section' },
      (props) => React.createElement('div', null, '我的设置页'),
    ))
  },
}
```

要点：

- `ctx.get('slots')` + 缺失检查（不要 `ctx.slots` 除非声明 inject）；
- `slots.inject` 等待 slot 声明生命周期，声明后注册；
- **先查询再注册**：用 Inspect 的 `Slots.listSubTree` 确认目标 slot 的存在、注册协议（single/list/keyed/chain）、作用域与 props，再写代码；
- 标准 props 提供会话数据：`useSession`/`useProjection`（session 作用域）、`useSessions`/`useWorkspaces`（全局）——数据已在 props 里就不要再加 Host RPC；
- 主题：`ctx.get('theme')` → `theme.overrideTokens('my-plugin', { light: {...}, dark: {...} })`（成对提供），或用 `styles.insert(css)` 与 `--dsw-*` 变量做局部样式；
- 设置页优先用 `settings.section` 获得完整内容区，`settings.general.item` 只适合单个紧凑偏好。

真实案例（`dsh-market` 插件商店）：客户端 bundle 手工编写（无构建步骤），`settings.section` 注册"插件市场"页，三个标签页（官方/社区/已安装），安装/卸载/更新操作带进度条与结果横幅，全部使用 `--dsw-alias-*` 主题变量。

**给插件自己开一张配置卡（`settings.plugin.item`，0.1.0-rc.7+）**：注册了 settings 命名空间的插件现在**天然出现在设置页**——api-proxy 服务每一个已注册命名空间（`WEB_SETTINGS_NAMESPACES`/`PRODUCT_SETTINGS_NAMESPACES` 白名单与 `settings-not-exposed` 错误码已删除），「插件」分区的 `configurable` 标签页声明 `settings.plugin.item`（**keyed，键 = 卡片所编辑的命名空间**）并按 `settings.describe` 返回的命名空间派发。浏览器半侧注册卡片：

```ts
ctx.slots.inject('settings.plugin.item', () => ctx.slots.register(
  { name: 'settings.plugin.item', key: '<你的 settings 命名空间>' },   // key，不是 id/order
  (props) => React.createElement('div', null, '我的插件配置'),
))
```

卡片外观、控件与文案全部由插件自己拥有（标签页不提供兜底表单）；卡片按注册顺序排列。Host 半注册命名空间 + 浏览器半把卡片注册在该键上，两者配对即出现在设置页——**仓库外分发的插件同样适用**，无需改动仓库。完整的可配置插件 = Host 注册 `ctx.settings.register(...)` 命名空间 + `dsh.client` 半注册上述 keyed 卡片。

## 19.5 模式五：Host↔Client 包私有 RPC

Host 注册处理器，Client 调用——**只走 JSON**：

```ts
// Host 半
return {
  apply(ctx) {
    harness.handle('market-status', async (args) => {
      return { installing: args.packageId, progress: 42 }
    })
  },
}

// Client 半
return {
  async apply(ctx) {
    const status = await host.call('market-status', { packageId: 'x' })
    console.log(status.progress)
  },
}
```

规则：参数与返回值必须无损 JSON（禁函数/React 元素/类实例/服务实例）；返回 null 表示无数据；不要用 `ctx.remote` 做包私有通信。

## 19.6 模式六：动态注册模型工具（harness）

Host 侧可动态注册"下一个模型步就能调用"的工具（动态插件的主要用途之一）：

```ts
return {
  apply(ctx) {
    harness.registerTool({
      name: 'my_dynamic_tool',
      description: '...',
      parameters: { /* JSON Schema */ },
      execute: async (args) => { return { ok: true } },
    })
  },
}
```

注册必须属于当前插件 Fiber——stop/update 后自动移除。先查 `Tool.listTools` 避免命名冲突。

## 19.7 模式七：后台作业

```ts
export function apply(ctx: Context) {
  const jobs = ctx.get('jobs')
  if (jobs === undefined) return
  jobs.start({
    kind: 'my-work',
    label: '长任务',
    owner: /* agent */,
    run: async (task) => {
      // 长工作；task.signal 响应取消
      return { done: true }
    },
  })
}
```

配套：`job_kill`/`job_list` 等通用控制工具由运行时提供；作业完成通过 `agent/*` 事件与 UI 的 jobs 面板呈现（第 16 章）。

## 19.8 模式八：注入模型可见上下文

```ts
// 在工具执行中
exec.agent.inject({
  content: '文件 changed: src/a.ts',
  source: { kind: 'plugin', plugin: 'my-watcher' },
})
```

`agent.inject()` 追加持久上下文，下一个模型请求可见——**它不是唤醒**（空闲 agent 保持空闲）；agent 已销毁时用 try/catch 保护。同类机制：`user/message` 事件里 `source.kind: 'plugin'` 的注入消息。

## 19.9 模式九：agent 预设内的插件

给"某个会话"装能力，把插件装进 preset 的 composition（第 16 章），而不是全局组合：

```yaml
# $DSH_HOME/.agent-presets/my-preset/cordis.yml
- id: my-tools
  name: my-tools
  config: {}
```

preset 插件注册在 agent 的 scope context 上：工具只对该 agent 可见、事件只收该 agent、卸载随 agent 销毁回卷。需要给 preset 内的 provider 与消费者共享独立服务实例时，用 `cordis:group` 包一个 `isolate` realm。

## 19.10 小结

九种模式覆盖了 dsh 插件开发的主要场景：工具（含呈现与后台化）、事件策略、能力三件套、客户端 UI、包私有 RPC、动态工具、后台作业、上下文注入、preset 内插件。写代码前用 Inspect 确认接口，写完记住"一切注册皆 effect"。下一章讲动态插件的工作流与故障修复。
