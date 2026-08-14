---
layout: home
hero:
  name: DeepSeek Harness
  text: 源码解析指南
  tagline: 从 Cordis 框架到核心子系统，再到插件开发技巧 —— 一本深入源码的中文技术书籍
  actions:
    - theme: brand
      text: 开始阅读
      link: /preface
    - theme: alt
      text: GitHub 仓库
      link: https://github.com/deepseek-ai/deepseek-harness
features:
  - icon: 🧩
    title: 一切皆插件
    details: 基于 Cordis 的插件化架构：模型适配器、工具注册表、会话日志、Agent 循环本身都是可替换的插件。
  - icon: 🔬
    title: 源码级解析
    details: 逐文件、逐行号地分析启动链路、事件系统、会话日志、Agent 状态机与工具执行管道。
  - icon: 🛠️
    title: 插件开发技巧
    details: 从插件形态、生命周期到动态插件工作流与最佳实践，配套真实代码示例与故障排查。
---

# 《DeepSeek Harness 源码解析指南》

本书以 **DeepSeek Harness（`dsh`）** 的开源代码库为对象，系统解析其架构设计与核心实现，并深入探讨基于其插件体系进行二次开发的技巧。

- **第一部分 · 全景与架构**：认识 dsh、仓库布局、总体架构
- **第二部分 · Cordis 框架源码解析**：Context 代理、Service、Fiber、事件系统、插件注册表
- **第三部分 · DSH 核心子系统源码解析**：启动链路、Profile/Bundle、会话日志、Agent 循环、工具系统、能力接缝
- **第四部分 · Web 客户端架构**：浏览器运行时、Slot、主题、RPC
- **第五部分 · 插件开发技巧**：开发基础、实战模式、动态插件工作流、最佳实践

> 本书对应源码版本：`deepseek-harness` 仓库 `0.1.0-rc.5/rc.6`（developer preview）。项目迭代迅速，存在破坏性变更，请以最新源码为准。

> 本书 Markdown 源文件托管在 GitHub：[anghunk/deepSeek-harness-docs](https://github.com/anghunk/deepSeek-harness-docs)，欢迎指正与参与修订。
