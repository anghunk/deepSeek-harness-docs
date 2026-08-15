# 第 1 章 认识 DeepSeek Harness

## 1.1 什么是 DeepSeek Harness

DeepSeek Harness（命令行工具名为 `dsh`）是 DeepSeek AI 开发的开源 Agent harness——一个承载、驱动并管理 AI 代理（Agent）的运行时环境。仓库地址为 <https://github.com/deepseek-ai/deepseek-harness>，采用 MIT 许可。

它不是一个"模型调用封装库"，而是一整套 **Agent 产品运行时**：

- 它管理会话（session）的完整生命周期：消息日志、持久化、恢复、分叉（fork）；
- 它驱动 Agent 循环：接收输入、组装提示词、调用模型、执行工具、处理流式输出；
- 它提供执行能力与安全边界：文件系统、子进程、终端、沙箱、审批策略；
- 它自带一个完整的 Web 图形界面（`dsh web`），同时支持无头（headless）与 ACP（Agent Client Protocol）等运行形态；
- 它还提供子代理、目标（goal）、计划（plan）、技能（skill）、上下文压缩等进阶机制。

而这一切，都建立在同一个插件框架之上：**[Cordis](https://github.com/cordiverse/cordis)**。dsh 官方这样描述自己的架构（`README.md`）：

> It uses an architecture where **everything is a plugin**, and is powered by Cordis.

"一切皆插件"——包括模型适配器、工具注册表、会话日志，甚至 Agent 循环本身（`docs/architecture.md`）：

> Every part of the product is a plugin, including the model adapter, the tool registry, the session log, and the agent loop itself, so every part is replaceable from configuration. There is no privileged core to patch: you extend dsh by mounting a plugin beside the others.

## 1.2 核心特性一览

| 特性 | 说明 |
| --- | --- |
| 插件化架构 | 基于 Cordis：服务（Service）、类型化事件（Event）、可逆副作用（Effect） |
| 事件溯源会话 | 会话是 append-only 的 `SessionEvent` 日志，模型历史由日志**派生**而非独立存储 |
| 可替换能力接缝 | fs、子进程、沙箱、终端、子代理等均为"定义 + 提供者 + 消费者"三件套 |
| 多运行形态 | `web`（浏览器 GUI）、`headless`（一次性命令行）、ACP（JSON-RPC stdio）、嵌入式 SDK |
| 双平面运行时 | Host（Node.js 进程）与 Client（浏览器）各有一套 Cordis 插件树 |
| 配置化组合 | Profile/Bundle/patch 分层，`cordis.patch.yml` 热更新，无需改代码即可重组产品 |
| 动态插件 | 会话内可创建、审批、更新、回滚动态 Cordis 插件，所见即所得地扩展运行时 |
| 内置工具集 | 文件系统、Bash、子进程、PTY 终端、后台作业、Web 搜索、技能等 |

## 1.3 快速上手

### 从 npm 运行

```sh
npx @deepseek-ai/dsh web
```

该命令启动 Web UI，默认服务在 <http://127.0.0.1:3080>。

### 从源码运行

```sh
git clone https://github.com/deepseek-ai/deepseek-harness.git
cd deepseek-harness
pnpm install
pnpm run build
pnpm dsh web
```

### 其他形态

```sh
# 一次性无头 Agent（需要 DEEPSEEK_API_KEY）
pnpm dsh --profile headless "summarize this workspace"

# 自指 demo：Agent 可以检查并修改自己正在运行的插件树
pnpm run demo:cordis

# ACP 自动化服务（JSON-RPC over stdio）
pnpm run demo:acp
```

## 1.4 版本状态与生态

- **开发者预览**：项目处于快速迭代期，官方明确声明存在破坏性变更；
- **社区**：GitHub Discussions、Discord 社区；
- **插件生态**：官方建议插件仓库添加 `dsh-plugin` topic 以便被发现；
- **上游**：Cordis 框架（vendor 目录内嵌）与 Cosmokit 工具库。

## 1.5 本书的源码地图

本书所有分析基于仓库根目录 `/Users/.../deepseek-harness`（写作时 commit `47f9438`）。后续章节将反复提到以下目录，先建立直觉：

| 目录 | 内容 |
| --- | --- |
| `apps/cli` | `dsh` 命令行入口（bin、profile-boot、plugin 子命令） |
| `apps/web` | Web 前端外壳（Vite + React） |
| `packages/core/*` | 核心：session、tools、agent、agent-loop、system-prompt、scope |
| `packages/llm/*` | LLM 消息词汇与适配器接缝（llm、llm-deepseek、llm-retry 等） |
| `packages/boot/*` | 启动组装（app-boot、cmdline）与三种 Bundle（base、web-app、headless） |
| `packages/host/*` | 宿主侧：Web 服务器、静态资源、插件清单 |
| `packages/client/*` | 浏览器侧运行时与全部 UI 组件包 |
| `packages/fs`、`packages/sandbox` 等 | 各类能力接缝 |
| `vendor/cordis` | 内嵌的 Cordis 框架源码（本书第二部分的主角） |
| `docs/` | 官方架构、子系统、cookbook 文档（含中文版） |
| `examples/` | 可运行的示例（web-cordis、headless-agent、mcp-memory、acp-agent 等） |

下一章，我们将展开这张地图。
