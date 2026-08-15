# 《DeepSeek Harness 源码解析指南》

一本由 **DeepSeek Harness（DSH）本身** 撰写的中文源码解析书籍，逐文件、逐行号地解析 `deepseek-ai/deepseek-harness` 的架构设计与核心实现，从 Cordis 框架到核心子系统，再到插件开发技巧。

## 为什么会有这本书

DeepSeek Harness 是一个承载、驱动并管理 AI 代理（Agent）的运行时环境，其插件化架构让模型适配器、工具注册表、会话日志、Agent 循环本身都可以被替换和扩展。

本书的初衷是用这套工具链**分析它自己**——让 DSH 以源码为对象，产出可读、可维护、可持续更新的中文解析文档。既是一份理解源码的"地图"与"方法论"，也是对 Agent 自主进行长文档工程实践的一次展示。

## 作者：DSH 本身

本书全部章节由 **DeepSeek Harness（`dsh`）** 以 headless Agent 模式自主分析源码后撰写：

- 逐文件、逐行号地阅读上游源码，提炼架构设计、事件流与关键机制；
- 章节按"全景与架构 → Cordis 框架 → 核心子系统 → Web 客户端 → 插件开发技巧 → 附录"组织；
- 每章包含真实代码引用、调用链与设计笔记，并随源码演进持续修订。

人类只负责选题与审核，文字与代码分析均由 Agent 完成。

## 每日自动同步

本书不是静态快照：每天凌晨 **00:00** 定时任务（launchd `com.dsh.docs-sync`）自动执行：

1. **拉取**：`git fetch` 上游 `deepseek-ai/deepseek-harness` 最新提交；
2. **增量检测**：与上次分析的提交对比，无更新则跳过（不空转）；
3. **增量分析**：有更新时，`dsh --profile headless` 只针对变更 diff 分析影响面，增量修订相关章节，不重写全书；
4. **变更记录**：每次同步在 [`changelog/`](changelog/) 下生成以日期命名的记录；
5. **提交推送**：自动 `git commit` 并 `push` 到本仓库；
6. **邮件通知**：发送每日报告（分析时间、是否有更新、分析内容、commit 等）。

> 源码仓库：[deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)（MIT 许可）
> 本书仓库：[anghunk/deepSeek-harness-docs](https://github.com/anghunk/deepSeek-harness-docs)

## 本地预览

```bash
npm install
npm run dev      # 开发预览（http://127.0.0.1:5173）
npm run build    # 静态构建
```
