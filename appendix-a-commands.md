# 附录 A 常用命令与配置

## A.1 dsh 命令

```sh
# 启动 Web UI（默认 http://127.0.0.1:3080）
dsh web

# 指定 profile
dsh --profile web
dsh --profile headless "summarize this workspace"   # 一次性无头 Agent

# 查看组合后的配置树（理解"机器实际启动了什么"的第一工具）
dsh --profile web --dump-config

# 插件管理子命令
dsh plugin ...          # 安装/卸载/管理插件

# 覆盖层
dsh web --patch ./extra.yml
```

环境变量：

| 变量 | 作用 |
| --- | --- |
| `DSH_HOME` | Harness 主目录（默认 `~/.dsh`） |
| `DEEPSEEK_API_KEY` | 模型 API 密钥 |
| `DEEPSEEK_BASE_URL` | 可选，覆盖 API 地址 |
| `DSH_TELEMETRY_DISABLED` | 任意非空值关闭遥测 |
| `DSH_SNAPSHOT` | `record`/`refresh`/`replay` 快照测试模式 |

## A.2 目录布局

```
~/.dsh/                          # Harness 主目录（默认）
├── profiles/                    # profile 目录（web、headless 模板）
│   └── web/
│       ├── package.json         # dsh.profile 清单（bundles 列表）
│       ├── cordis.yml           # 空根配置（只用于锚定 baseUrl）
│       └── cordis.patch.yml     # 用户 patch 层（热更新）
├── cordis.patch.yml             # 用户级 patch（所有 profile 生效）
└── .agent-presets/<id>/         # agent 预设
    ├── package.json             # dsh.preset 元数据
    └── cordis.yml               # 该预设的插件组合
```

## A.3 Profile 清单字段

```jsonc
// profile 的 package.json
{
  "dsh": {
    "profile": {
      "bundles": ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app"],
      // 可选：额外插件依赖
    }
  }
}
```

## A.4 Patch 文件语法

```yaml
# cordis.patch.yml —— 顶层 YAML 数组
- id: session-telemetry-otel      # 按 id 整行替换
  config: { enabled: false }

- insert:                          # 插入新行
    - id: my-plugin
      name: my-plugin
      config:
        key: !!js process.env.MY_KEY   # !!js 表达式在激活时求值
```

## A.5 仓库开发命令

```sh
pnpm install                 # 安装（含 lefthook 钩子）
pnpm run build               # 完整构建（host lib + client lib + web）
pnpm run typecheck           # 类型检查（含 Typert 契约生成）
pnpm test                    # 单元/集成测试
pnpm run test:e2e            # 真实 API e2e（需 DEEPSEEK_API_KEY）
pnpm run hygiene             # knip/publint/constraints 等卫生门禁
pnpm run check:all           # 全部门禁
pnpm run docs:dev            # 官方文档站（VitePress）
pnpm dsh web                 # 从源码跑 web
pnpm run demo:cordis         # 自指 cordis demo
pnpm run demo:acp            # ACP 服务 demo
```

## A.6 官方文档索引（仓库 docs/）

| 文件 | 内容 |
| --- | --- |
| `architecture.md` | 总架构（必读） |
| `cordis-primer.md` / `cordis-tutorial/` | Cordis 入门 |
| `subsystems/*.md` | 各子系统深度文档（含生成的服务/事件目录） |
| `cookbook/` | 扩展 cookbook（加包/工具/LLM 适配器/对话节点） |
| `config-catalog.md` | 全部可配置字段（生成） |
| `event-producer-consumer.md` | 事件生产者/消费者（生成） |
| `tool-catalog.md` | 工具 schema 目录（生成） |
| `persistence-catalog.md` | 持久化事件目录（生成） |
| `module-graph.md` | 包依赖图（生成） |
| `glossary.md` | 术语表 |
| `testing.md` / `development.md` | 测试与开发指南 |
