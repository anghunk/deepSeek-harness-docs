# VitePress "更新时间" 问题分析

## 本地构建验证 ✅

我刚刚在本地构建并验证，**时间戳完全正确**：

| 文件 | 显示时间 | Git 提交时间 | 匹配 |
|------|---------|-------------|------|
| preface.md | 2026-08-15 15:16:32 | 2026-08-15 15:16:32 | ✓ |
| ch1-overview.md | 2026-08-15 14:23:42 | 2026-08-15 14:23:42 | ✓ |
| ch8-boot-chain.md | 2026-08-20 13:47:11 | 2026-08-20 13:47:11 | ✓ |
| changelog/2026-08-19.md | 2026-08-20 13:47:11 | 2026-08-20 13:47:11 | ✓ |

不同文件显示不同的 git 提交时间，这是正确的行为。

## 你看到的问题

你说"每个页面都是同一个时间"，这说明你看到的构建环境中 **git 历史不完整**。

## 根本原因

VitePress 的 `lastUpdated` 功能在构建时通过 `git log` 获取每个文件的最后提交时间。如果构建环境是 **shallow clone**（浅克隆），只有最新一次 commit，那么所有文件都会返回同一个时间戳。

### 什么是 shallow clone？

```bash
# 这些都会导致 shallow clone：
git clone --depth=1 https://github.com/...  # 显式 shallow
actions/checkout@v4  # GitHub Actions 默认 fetch-depth: 1
```

Shallow clone 只下载最新的 1 个 commit，`git log` 只能看到这 1 个 commit，所以所有文件都显示同一个时间。

## 解决方案

### 场景 1：GitHub Actions 部署

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      fetch-depth: 0  # ← 关键：获取完整历史
```

### 场景 2：服务器手动部署

```bash
# ❌ 错误
git clone --depth=1 https://github.com/anghunk/deepseek-harness-docs.git

# ✅ 正确
git clone https://github.com/anghunk/deepseek-harness-docs.git
cd deepseek-harness-docs
npm install
npm run build
```

如果已经是 shallow clone，可以修复：
```bash
git fetch --unshallow
```

### 场景 3：Netlify / Vercel

这些平台通常自动获取完整历史。如果仍有问题，检查构建设置中的 "Shallow clone" 选项（关闭它）。

## 快速诊断

在你的部署环境（服务器或 CI）中运行：

```bash
# 检查是否为 shallow clone
git rev-parse --is-shallow-repository
# 如果输出 true，说明是 shallow clone

# 检查 commit 数量
git log --oneline | wc -l
# 如果输出 1，说明只有 1 个 commit
```

## 临时禁用 lastUpdated

如果你暂时不需要这个功能，可以在 `.vitepress/config.mts` 中禁用：

```javascript
export default defineConfig({
  // ...
  lastUpdated: false,  // 禁用
  themeConfig: {
    // ...
    // lastUpdated: { text: '更新于' },  // 注释掉这行
  }
})
```

---

**总结**：本地构建是正确的，问题出在部署环境的 git 历史不完整。确保部署时获取完整 git 历史即可解决。
