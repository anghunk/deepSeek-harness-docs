#!/bin/bash
# ============================================================
# dsh 上游源码同步 + 文档增量更新脚本
#
# 流程：
#   1. 确保源码仓库已 clone（首次）或 fetch + pull
#   2. 与上次分析 SHA 对比，无新提交则直接退出（不分析）
#   3. 有更新：生成增量变更摘要（提交列表 + diff，超限截断）
#   4. 用 dsh headless 分析变更，增量更新 docs 相关章节并提交
#   5. 记录本次分析的 SHA 与时间
#
# 由 launchd（com.dsh.docs-sync）每天 00:00 触发，也可手动执行：
#   bash scripts/sync-source.sh [--dry-run]
# ============================================================
set -uo pipefail

# ---------- 配置 ----------
SOURCE_REPO="https://github.com/deepseek-ai/deepseek-harness.git"
SOURCE_DIR="/Users/abc/code/demo/dsh-source"
DOCS_DIR="/Users/abc/code/demo/dsh/docs"
STATE_DIR="${HOME}/.dsh-sync"
STATE_FILE="${STATE_DIR}/state.json"
LOG_FILE="${STATE_DIR}/sync.log"
SUMMARY_DIR="${STATE_DIR}/summaries"
CRED_FILE="${HOME}/.dsh/.credentials.yaml"
MAX_COMMITS=40            # 首次/兜底最多分析的提交数
MAX_DIFF_BYTES=300000     # diff 摘要超过 300KB 截断
DRY_RUN="${1:-}"

mkdir -p "${STATE_DIR}" "${SUMMARY_DIR}"
log() { echo "[$(date '+%F %T')] $*" >> "${LOG_FILE}"; }
info() { log "$*"; echo "$*"; }
die()  { log "错误: $*"; echo "错误: $*" >&2; exit 1; }

info "===== 开始同步 ====="

# ---------- 1. 确保源码仓库 ----------
if [ ! -d "${SOURCE_DIR}/.git" ]; then
  info "首次运行：clone 源码仓库到 ${SOURCE_DIR} ..."
  git clone --filter=blob:none "${SOURCE_REPO}" "${SOURCE_DIR}" >> "${LOG_FILE}" 2>&1 \
    || die "clone 失败，请检查网络"
else
  info "fetch 上游更新 ..."
  git -C "${SOURCE_DIR}" fetch origin >> "${LOG_FILE}" 2>&1 \
    || die "fetch 失败，请检查网络"
fi

CURRENT_SHA=$(git -C "${SOURCE_DIR}" rev-parse FETCH_HEAD 2>/dev/null || git -C "${SOURCE_DIR}" rev-parse HEAD)
CURRENT_DATE=$(git -C "${SOURCE_DIR}" log -1 --format=%cd --date=short "${CURRENT_SHA}" 2>/dev/null)

# ---------- 2. 增量检测 ----------
LAST_SHA=""
if [ -f "${STATE_FILE}" ]; then
  LAST_SHA=$(python3 -c "import json;print(json.load(open('${STATE_FILE}')).get('last_sha',''))" 2>/dev/null || echo "")
fi

if [ -n "${LAST_SHA}" ] && [ "${LAST_SHA}" = "${CURRENT_SHA}" ]; then
  info "无更新（HEAD 仍为 ${CURRENT_SHA}，${CURRENT_DATE}），跳过分析"
  exit 0
fi

# 首次运行（无基线）：只建立基线，不分析（文档按当前版本写作，无增量可言）
if [ -z "${LAST_SHA}" ]; then
  info "首次运行：建立基线 ${CURRENT_SHA}（${CURRENT_DATE}），跳过分析"
  python3 - "${STATE_FILE}" "${CURRENT_SHA}" <<'PYEOF' >> "${LOG_FILE}" 2>&1
import json, sys, datetime
state_file, sha = sys.argv[1], sys.argv[2]
try:
    state = json.load(open(state_file))
except Exception:
    state = {}
state["last_sha"] = sha
state["last_sync_at"] = datetime.datetime.now().isoformat(timespec="seconds")
json.dump(state, open(state_file, "w"), indent=2, ensure_ascii=False)
print(f"状态已更新: last_sha={sha}")
PYEOF
  exit 0
fi

info "检测到更新：上次 ${LAST_SHA} → 本次 ${CURRENT_SHA}（${CURRENT_DATE}）"

# pull 到工作区（dry-run 也拉，保证后续手动分析可用）
git -C "${SOURCE_DIR}" pull --ff-only >> "${LOG_FILE}" 2>&1 || die "pull 失败"

# ---------- 3. 生成增量变更摘要 ----------
STAMP=$(date '+%Y%m%d-%H%M%S')
SUMMARY_FILE="${SUMMARY_DIR}/changes-${STAMP}.md"

{
  echo "# 上游变更摘要 ${CURRENT_SHA}（${CURRENT_DATE}）"
  echo
  echo "分析范围：${LAST_SHA} → ${CURRENT_SHA}"
  echo
  echo "## 提交列表"
  git -C "${SOURCE_DIR}" log --oneline --no-decorate "${LAST_SHA}..${CURRENT_SHA}" | head -"${MAX_COMMITS}"
  echo
  echo "## 变更统计"
  git -C "${SOURCE_DIR}" diff --stat "${LAST_SHA}".."${CURRENT_SHA}" | tail -30
  echo
  echo "## 变更 diff（可能截断）"
  git -C "${SOURCE_DIR}" diff "${LAST_SHA}".."${CURRENT_SHA}"
} > "${SUMMARY_FILE}" 2>> "${LOG_FILE}"

SIZE=$(wc -c < "${SUMMARY_FILE}")
if [ "${SIZE}" -gt "${MAX_DIFF_BYTES}" ]; then
  head -c "${MAX_DIFF_BYTES}" "${SUMMARY_FILE}" > "${SUMMARY_FILE}.trim"
  mv "${SUMMARY_FILE}.trim" "${SUMMARY_FILE}"
  echo -e "\n\n> ⚠️ diff 超过 ${MAX_DIFF_BYTES} 字节已截断，必要时直接查阅源码仓库" >> "${SUMMARY_FILE}"
  info "diff 摘要已截断（${SIZE} 字节 → ${MAX_DIFF_BYTES}）"
fi
info "增量摘要已生成：${SUMMARY_FILE}（$(wc -l < "${SUMMARY_FILE}") 行）"

# ---------- 4. dry-run 结束 ----------
if [ "${DRY_RUN}" = "--dry-run" ]; then
  info "[dry-run] 跳过 headless 分析与文档更新"
  exit 0
fi

# ---------- 5. dsh headless 分析并更新文档 ----------
[ -f "${CRED_FILE}" ] || die "凭据文件不存在: ${CRED_FILE}"
export OPENCODE_GO_API_KEY=$(
  grep '^OPENCODE_GO_API_KEY:' "${CRED_FILE}" | head -1 \
  | sed 's/^OPENCODE_GO_API_KEY:[[:space:]]*//' | tr -d '"'"'"' '
)
[ -n "${OPENCODE_GO_API_KEY:-}" ] || die "凭据文件中未找到 OPENCODE_GO_API_KEY"

RANGE_LABEL="${LAST_SHA:0:12}..${CURRENT_SHA:0:12}"
PROMPT="你是 DeepSeek Harness 源码解析文档（VitePress 书籍）的维护 agent。

上游源码仓库 ${SOURCE_DIR} 刚更新。增量变更摘要（提交列表 + diff，可能截断）位于：
${SUMMARY_FILE}

文档项目位于 ${DOCS_DIR}（当前工作目录）。书籍章节按目录组织：part1-architecture/（ch1-3 全景与架构）、part2-cordis/（ch4-7 Cordis 框架）、part3-core/（ch8-16 核心子系统）、part4-web/（ch17）、part5-plugins/（ch18-21 插件开发）、appendix/（附录）、preface.md、index.md。

任务（增量更新，切勿全量重写）：
1. 阅读变更摘要，必要时查阅 ${SOURCE_DIR} 源码，判断影响哪些章节（架构、Cordis、核心子系统、Web 客户端、插件开发技巧、附录）。
2. 只修改受影响的章节文件：补充新机制/新文件，修正与新版不符的过时描述（如路径、API、行为变化）。不重写整章，不动无关内容；无对应章节影响的变更不强行改文档。
3. 在 ${DOCS_DIR}/changelog/ 创建或追加变更记录：文件 ${DOCS_DIR}/changelog/${CURRENT_DATE}.md，列出本次上游提交（范围 ${RANGE_LABEL}）与对文档的改动摘要。
4. 在 ${DOCS_DIR} 中 git add 并 commit（message 含日期与提交范围，如 \"docs: 同步上游 ${CURRENT_DATE}（${RANGE_LABEL}）\"）。不要 push。
5. 输出总结：改动了哪些文件、对应上游哪些提交、哪些变更未影响文档及原因。"

info "启动 dsh headless 分析（提交范围 ${RANGE_LABEL}）..."
cd "${DOCS_DIR}" || die "无法进入文档目录 ${DOCS_DIR}"
if dsh --profile headless "${PROMPT}" >> "${LOG_FILE}" 2>&1; then
  info "headless 分析完成"
else
  die "headless 分析失败（退出码 $?），详见 ${LOG_FILE}"
fi

# ---------- 6. 记录状态 ----------
python3 - "${STATE_FILE}" "${CURRENT_SHA}" <<'PYEOF' >> "${LOG_FILE}" 2>&1
import json, sys, datetime
state_file, sha = sys.argv[1], sys.argv[2]
try:
    state = json.load(open(state_file))
except Exception:
    state = {}
state["last_sha"] = sha
state["last_sync_at"] = datetime.datetime.now().isoformat(timespec="seconds")
json.dump(state, open(state_file, "w"), indent=2, ensure_ascii=False)
print(f"状态已更新: last_sha={sha}")
PYEOF

info "===== 同步完成（${CURRENT_SHA}，${CURRENT_DATE}）====="
