# DSH 文档同步逻辑参考文档

本文档整理自 `scripts/sync-source.sh`（280 行），供在其他客户端重放同步逻辑使用。

---

## 1. 整体流程

1. 拉取上游源码仓库（首次 clone / 后续 fetch + pull）
2. 读取上次同步的 SHA（state.json）
3. 比较 SHA：
   - 相同 → 发"无更新"邮件 → 退出
   - 首次 → 建立基线 → 发"首次运行"邮件 → 退出
   - 不同 → 继续
4. 生成增量变更摘要（commits + diff，可能截断）
5. 调用 dsh headless 分析变更 → 增量更新文档
6. git commit + push 到 GitHub
7. 发送分析报告邮件
8. 更新 state.json

---

## 2. 关键路径

| 项目 | 路径 |
|------|------|
| 上游源码 | `https://github.com/deepseek-ai/deepseek-harness.git` → 本地 `/Users/abc/code/demo/dsh-source` |
| 文档仓库 | `/Users/abc/code/demo/dsh/docs` |
| 同步状态 | `~/.dsh-sync/state.json`（`last_sha` + `last_sync_at`） |
| 日志 | `~/.dsh-sync/sync.log` |
| 变更摘要 | `~/.dsh-sync/summaries/changes-<timestamp>.md` |
| 分析输出 | `~/.dsh-sync/analysis-<timestamp>.txt` |
| 邮件模板 | `scripts/mail-template.html` |
| dsh 凭据 | `~/.dsh/.credentials.yaml` |
| dsh 配置 | `~/.dsh/settings.yaml` |

---

## 3. Headless 分析 Prompt（核心）

这是传给 `dsh --profile headless` 的完整 prompt。在其他客户端重放时，直接复用此 prompt 即可：

```text
你是 DeepSeek Harness 源码解析文档（VitePress 书籍）的维护 agent。

上游源码仓库 <SOURCE_DIR> 刚更新。增量变更摘要（提交列表 + diff，可能截断）位于：
<SUMMARY_FILE>

文档项目位于 <DOCS_DIR>（当前工作目录）。书籍章节按目录组织：
- part1-architecture/（ch1-3 全景与架构）
- part2-cordis/（ch4-7 Cordis 框架）
- part3-core/（ch8-16 核心子系统）
- part4-web/（ch17）
- part5-plugins/（ch18-21 插件开发技巧）
- appendix/（附录）
- preface.md、index.md

任务（增量更新，切勿全量重写）：
1. 阅读变更摘要，必要时查阅 <SOURCE_DIR> 源码，判断影响哪些章节。
2. 只修改受影响的章节文件：补充新机制/新文件，修正与新版不符的过时描述。
   不重写整章，不动无关内容；无对应章节影响的变更不强行改文档。
3. 在 <DOCS_DIR>/changelog/ 创建或追加变更记录：
   文件 <DOCS_DIR>/changelog/<CURRENT_DATE>.md，第一行标题用日期（# <CURRENT_DATE>），
   随后列出本次上游提交（范围 <RANGE_LABEL>）与对文档的改动摘要；
   若该日期文件已存在则在其基础上追加本次内容。不要修改 changelog/index.md。
4. 在 <DOCS_DIR> 中 git add 并 commit（message 含日期与提交范围，
   如 "docs: 同步上游 <CURRENT_DATE>（<RANGE_LABEL>）"）。不要 push。
5. 输出总结：改动了哪些文件、对应上游哪些提交、哪些变更未影响文档及原因。
```

**调用方式**：
```bash
cd <DOCS_DIR>
dsh --profile headless "<上述 prompt>"
```

---

## 4. API Key 处理

### 当前实现

脚本从 `~/.dsh/.credentials.yaml` 提取 `OPENCODE_GO_API_KEY` 并 export：

```bash
export OPENCODE_GO_API_KEY=$(
  grep '^OPENCODE_GO_API_KEY:' ~/.dsh/.credentials.yaml | head -1 \
  | sed 's/^OPENCODE_GO_API_KEY:[[:space:]]*//' | tr -d '"\'' '
)
```

### 为什么必须手动 export

经实测，`dsh --profile headless` 启动的 agent session **不会**自动把 `.credentials.yaml` 里的 key 注入为环境变量。脚本必须显式 export，否则 agent 读不到 API key。

### 如何支持多 provider

如果你在其他客户端使用不同的 provider，需要 export 对应的 key：

| Provider | apiKeyEnv |
|----------|-----------|
| opencode-go | OPENCODE_GO_API_KEY |
| flygu | FLYGU_API_KEY |
| alibailian-codingplan | ALIBAILIAN_CODINGPLAN_API_KEY |

**建议改进**（provider-agnostic）：export 所有 `_API_KEY` 结尾的 key：

```bash
while IFS= read -r line; do
  key=$(echo "$line" | sed 's/:.*//')
  val=$(echo "$line" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '"\'')
  [ -n "$val" ] && export "$key=$val"
done < <(grep '_API_KEY:' ~/.dsh/.credentials.yaml)
```

---

## 5. 增量检测逻辑

```bash
# 读取上次 SHA
LAST_SHA=$(python3 -c "import json;print(json.load(open('~/.dsh-sync/state.json')).get('last_sha',''))")

# 获取当前 HEAD
CURRENT_SHA=$(git -C <SOURCE_DIR> rev-parse FETCH_HEAD)

# 比较
if [ "$LAST_SHA" = "$CURRENT_SHA" ]; then
  # 无更新 → 发邮件 → 退出
elif [ -z "$LAST_SHA" ]; then
  # 首次 → 建基线 → 发邮件 → 退出
else
  # 有更新 → 继续
fi
```

---

## 6. 变更摘要生成

```bash
SUMMARY_FILE=~/.dsh-sync/summaries/changes-$(date '+%Y%m%d-%H%M%S').md

{
  echo "# 上游变更摘要 $CURRENT_SHA ($CURRENT_DATE)"
  echo
  echo "分析范围：$LAST_SHA → $CURRENT_SHA"
  echo
  echo "## 提交列表"
  git -C <SOURCE_DIR> log --oneline --no-decor "$LAST_SHA..$CURRENT_SHA" | head -40
  echo
  echo "## 变更统计"
  git -C <SOURCE_DIR> diff --stat "$LAST_SHA..$CURRENT_SHA" | tail -30
  echo
  echo "## 变更 diff（可能截断）"
  git -C <SOURCE_DIR> diff "$LAST_SHA..$CURRENT_SHA"
} > "$SUMMARY_FILE"

# 超过 300KB 截断
if [ $(wc -c < "$SUMMARY_FILE") -gt 300000 ]; then
  head -c 300000 "$SUMMARY_FILE" > "$SUMMARY_FILE.trim"
  mv "$SUMMARY_FILE.trim" "$SUMMARY_FILE"
  echo -e "\n\n> ⚠️ diff 超过 300000 字节已截断" >> "$SUMMARY_FILE"
fi
```

---

## 7. 邮件通知

### 无更新简报

```bash
send_simple_mail "[DSH 文档同步] $(date '+%m-%d') 无上游更新" \
"<b>分析时间：</b>$(date '+%F %T')<br/>
<b>上游是否有更新：</b>❌ 无更新<br/>
<b>本次是否产生新分析：</b>否（上游 HEAD 无变化，已跳过）<br/><br/>
文档无变更，无需处理。"
```

### 分析报告（成功）

使用 `mail-template.html` 渲染，变量包括：
- `SYNC_TIME`、`HAS_UPDATE`、`HAS_ANALYSIS`
- `RANGE`（提交范围 + 数量）
- `COMMITS_LIST`（提交列表）
- `ANALYSIS_SUMMARY`（headless 输出前 60 行）
- `DOC_CHANGES`（git show --stat）
- `COMMITTED`、`PUSHED`、`COMMIT_SHA`、`COMMIT_MSG`

渲染逻辑见 `render_mail()`（Python 内联脚本，读取变量目录、替换模板占位符、HTML 转义）。

### 分析报告（失败）

```bash
send_simple_mail "[DSH 文档同步] $CURRENT_DATE 上游分析失败" \
"<b>分析时间：</b>$(date '+%F %T')<br/>
<b>上游是否有更新：</b>✅ 有更新（$RANGE_LABEL）<br/>
<b>本次是否产生新分析：</b>❌ 分析失败（headless 退出码非 0）<br/><br/>
文档未修改，状态未推进，下次运行将重试。详见日志：<code>$LOG_FILE</code>"
```

---

## 8. 状态管理

`state.json` 结构：
```json
{
  "last_sha": "99f6f02fecdb7dff40c3fbc9470f5907c29f74ca",
  "last_sync_at": "2026-08-18T00:05:47"
}
```

**更新时机**：仅在 headless 分析成功、git commit 完成后更新。分析失败时不更新，下次运行会重试同一范围。

---

## 9. 在其他客户端重放的步骤

1. **Clone 上游源码**：`git clone https://github.com/deepseek-ai/deepseek-harness.git`
2. **Clone 文档仓库**：`git clone https://github.com/anghunk/deepseek-harness-docs.git`
3. **安装 dsh**：`npm install -g @deepseek-ai/dsh`（或其他客户端提供的 dsh 兼容实现）
4. **配置凭据**：创建 `~/.dsh/.credentials.yaml`，填入 `OPENCODE_GO_API_KEY`（或其他 provider 的 key）
5. **配置 settings**（可选）：`~/.dsh/settings.yaml`，定义 provider 和 model
6. **运行同步脚本**：参考 `sync-source.sh` 的逻辑，或直接用上述 prompt 手动触发 headless 分析

---

## 10. 注意事项

- **diff 可能很大**：当前设置 300KB 截断，536 commits 的 diff 达 6.4MB
- **headless 分析耗时**：大变更可能需要 5-15 分钟
- **失败不推进状态**：分析失败时 `state.json` 不变，下次会重试
- **邮件发送失败不阻塞主流程**：`send_mail` 只记日志，不 die
- **dry-run 模式**：`bash scripts/sync-source.sh --dry-run` 只生成摘要，不触发 headless

---

## 附录：完整脚本路径

- 主脚本：`/Users/abc/code/demo/dsh/docs/scripts/sync-source.sh`
- 邮件模板：`/Users/abc/code/demo/dsh/docs/scripts/mail-template.html`
- launchd plist：`~/Library/LaunchAgents/com.dsh.docs-sync.plist`
