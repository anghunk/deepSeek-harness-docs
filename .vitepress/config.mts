import { defineConfig } from 'vitepress'
import { withMermaid } from 'vitepress-plugin-mermaid'

const guide = 'DeepSeek Harness'

const sidebar = [
  {
    text: '关于本书',
    items: [
      { text: '前言', link: '/preface' },
    ],
  },
  {
    text: '第一部分 · 全景与架构',
    items: [
      { text: '第 1 章 认识 DeepSeek Harness', link: '/part1-architecture/ch1-overview' },
      { text: '第 2 章 仓库全景', link: '/part1-architecture/ch2-repo-layout' },
      { text: '第 3 章 总体架构', link: '/part1-architecture/ch3-architecture' },
    ],
  },
  {
    text: '第二部分 · Cordis 框架源码解析',
    items: [
      { text: '第 4 章 Context 与反射层', link: '/part2-cordis/ch4-cordis-context' },
      { text: '第 5 章 Service 与 Fiber 生命周期', link: '/part2-cordis/ch5-cordis-service-fiber' },
      { text: '第 6 章 事件系统与派发模式', link: '/part2-cordis/ch6-cordis-events' },
      { text: '第 7 章 插件注册表', link: '/part2-cordis/ch7-cordis-registry' },
    ],
  },
  {
    text: '第三部分 · DSH 核心子系统源码解析',
    items: [
      { text: '第 8 章 启动链路', link: '/part3-core/ch8-boot-chain' },
      { text: '第 9 章 Profile 与 Bundle 组合机制', link: '/part3-core/ch9-profile-bundle' },
      { text: '第 10 章 会话日志：事件溯源核心', link: '/part3-core/ch10-session-log' },
      { text: '第 11 章 Agent 循环：turn/step 状态机', link: '/part3-core/ch11-agent-loop' },
      { text: '第 12 章 工具系统与执行管道', link: '/part3-core/ch12-tools' },
      { text: '第 13 章 提示词组装与作用域', link: '/part3-core/ch13-system-prompt-scope' },
      { text: '第 14 章 LLM 适配器接缝', link: '/part3-core/ch14-llm-seam' },
      { text: '第 15 章 能力接缝：执行与沙箱', link: '/part3-core/ch15-capability-seams' },
      { text: '第 16 章 代理预设、目标与子代理', link: '/part3-core/ch16-preset-goal-subagent' },
    ],
  },
  {
    text: '第四部分 · Web 客户端架构',
    items: [
      { text: '第 17 章 Web 客户端与 UI 架构', link: '/part4-web/ch17-web-client' },
    ],
  },
  {
    text: '第五部分 · 插件开发技巧',
    items: [
      { text: '第 18 章 插件开发基础', link: '/part5-plugins/ch18-plugin-basics' },
      { text: '第 19 章 插件开发实战模式', link: '/part5-plugins/ch19-plugin-patterns' },
      { text: '第 20 章 动态插件工作流与诊断修复', link: '/part5-plugins/ch20-dynamic-plugin-workflow' },
      { text: '第 21 章 最佳实践与调试', link: '/part5-plugins/ch21-plugin-best-practices' },
    ],
  },
  {
    text: '附录',
    items: [
      { text: '附录 A 常用命令与配置', link: '/appendix/appendix-a-commands' },
      { text: '附录 B 术语表', link: '/appendix/appendix-b-glossary' },
      { text: '附录 C 参考资源', link: '/appendix/appendix-c-references' },
    ],
  },
]

export default withMermaid(
  defineConfig({
    lang: 'zh-CN',
    title: guide,
    description: 'DeepSeek Harness 源码解析指南：从 Cordis 框架到核心子系统，再到插件开发技巧',
    cleanUrls: true,
    lastUpdated: true,
    head: [
      ['meta', { name: 'theme-color', content: '#4d6bfe' }],
    ],
    themeConfig: {
      logo: '/dsh-logo.svg',
      nav: [
        { text: '首页', link: '/' },
        { text: '目录', link: '/preface' },
        { text: 'DeepSeek Harness 源码', link: 'https://github.com/deepseek-ai/deepseek-harness' },
        { text: '文档仓库', link: 'https://github.com/anghunk/deepSeek-harness-docs' },
      ],
      sidebar,
      outline: { level: [2, 3], label: '本章目录' },
      docFooter: { prev: '上一章', next: '下一章' },
      lastUpdated: { text: '更新于' },
      editLink: {
        text: '在 GitHub 上编辑此页',
        pattern: 'https://github.com/anghunk/deepSeek-harness-docs/edit/main/:path',
      },
      search: {
        provider: 'local',
        options: {
          translations: {
            button: { buttonText: '搜索', buttonAriaLabel: '搜索' },
            modal: { noResultsText: '未找到相关内容', resetButtonTitle: '清除', footer: { selectText: '选择', navigateText: '切换', closeText: '关闭' } },
          },
        },
      },
      footer: {
        message: '基于 MIT 许可的 DeepSeek Harness 源码撰写的独立解析书籍',
        copyright: 'Copyright © 2026',
      },
    },
    mermaid: {
      theme: 'neutral',
    },
  }),
)
