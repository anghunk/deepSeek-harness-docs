# 附录 C 参考资源

## 本书仓库

- **Markdown 源文件**：<https://github.com/anghunk/deepSeek-harness-docs>
- 发现错误或希望参与修订，欢迎在该仓库提交 issue 或 PR。

## 官方资源

- **仓库**：<https://github.com/deepseek-ai/deepseek-harness>
- **Cordis 框架**：<https://github.com/cordiverse/cordis>
- **Cordis 设计论文**（*A Programming Paradigm for Spatiotemporal Composability*）：<https://github.com/cordiverse/paper>
- **npm 包**：`@deepseek-ai/dsh`（`npx @deepseek-ai/dsh web`）
- **讨论区**：<https://github.com/deepseek-ai/deepseek-harness/discussions>
- **Discord**：<https://discord.gg/Ycq5dCaS4>
- **插件发现**：GitHub topic [`dsh-plugin`](https://github.com/topics/dsh-plugin)

## 仓库内一手资料（写作时快照）

| 资料 | 位置 |
| --- | --- |
| 总架构 | `docs/architecture.md`（含中文版） |
| Cordis 入门 | `docs/cordis-primer.md`、`docs/cordis-tutorial/` |
| 子系统深度文档 | `docs/subsystems/*.md`（含生成的服务/事件目录） |
| 扩展 cookbook | `docs/cookbook/extension-cookbook.md` 及 `adding-a-*.md` |
| 生命周期时序 | `docs/agent-lifecycle.md`、`docs/tool-execution-pipeline.md` |
| 配置/事件/工具/持久化目录 | `docs/config-catalog.md`、`docs/event-producer-consumer.md`、`docs/tool-catalog.md`、`docs/persistence-catalog.md` |
| 设计决策笔记 | `.agents/notes/`（implemented/architecture、bug-fix、simplification 等） |
| 示例 | `examples/`（web-cordis、headless-agent、mcp-memory、acp-agent、web-schedule） |

## 本书引用版本

- 仓库 commit：`47f9438`（Merge pull request #2519）
- 版本：`0.1.0-rc.5` / `0.1.0-rc.6`（developer preview）

> 项目迭代迅速，阅读本书时如与最新源码不一致，请以仓库为准。本书的价值在于提供理解路径与源码索引，而非一份永不失效的 API 手册。
