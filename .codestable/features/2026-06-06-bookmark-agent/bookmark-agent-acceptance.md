# GitHub Agent 功能验收手册

## 验收环境

| 项目 | 值 |
|------|-----|
| 线上地址 | http://124.222.143.123:3000 |
| CLI | `karakeep agent`（需在服务器上执行） |
| 部署版本 | `karakeep-custom:latest`（`273881fe`） |

## 验收清单

### 1. 自动检测 + 创建项目书签

**如何测试：**
1. 收藏一篇**包含 GitHub 链接**的文章（如某个博客里提到了 `github.com/facebook/react`）
2. 等待爬虫 + AI 分类完成后
3. 在书签列表中找到刚刚收藏的文章

**预期结果：**
- 该文章的卡片下方显示新的书签卡片（标题为 `facebook/react`）
- 该书签卡片上有 Github 徽章：⭐ 星数 · 🔵 语言 · 话题标签
- 打开该书签链接，跳转到 GitHub 项目页

**判定：** ✅ 通过 / ❌ 不通过

---

### 2. 收藏 GitHub 项目链接

**如何测试：**
1. 直接收藏一个 GitHub 项目 URL（如 `https://github.com/vercel/next.js`）
2. 等待爬虫 + AI 分类完成后

**预期结果：**
- 书签卡片上有 Github 徽章：⭐ · 🔵 TypeScript · ⚖️ MIT
- 点开书签详情，摘要（summary）是对项目的简短描述

**判定：** ✅ 通过 / ❌ 不通过

---

### 3. Agent CLI - 搜索项目

**在服务器上执行：**
```bash
docker exec karakeep-web-1 node /app/apps/cli/index.mjs agent find --query react
docker exec karakeep-web-1 node /app/apps/cli/index.mjs agent find --query rust --language TypeScript
docker exec karakeep-web-1 node /app/apps/cli/index.mjs agent find --min-stars 10000 --json
```

**预期结果：**
- 返回已收藏的 GitHub 项目列表
- `--json` 输出合法的 JSON
- 支持按语言、最低星数筛选

**判定：** ✅ 通过 / ❌ 不通过

---

### 4. Agent CLI - 项目详情

```bash
docker exec karakeep-web-1 node /app/apps/cli/index.mjs agent project facebook/react --json
```

**预期结果：**
- 返回项目的 GitHub 元数据（fullName, stars, language, topics, license）
- 如果 AI 已分析过，包含 `humanSummary` 和 `agentDossier`

**判定：** ✅ 通过 / ❌ 不通过

---

### 5. Agent CLI - 推荐

```bash
docker exec karakeep-web-1 node /app/apps/cli/index.mjs agent recommend "我想找一个 Rust 写的静态博客生成器"
```

**预期结果：**
- 返回基于已收藏项目的推荐列表
- 每条推荐包含项目名、星数和简短理由

**判定：** ✅ 通过 / ❌ 不通过

---

### 6. Agent CLI - 画像

```bash
docker exec karakeep-web-1 node /app/apps/cli/index.mjs agent profile
```

**预期结果：**
- 返回基于已收藏 GitHub 项目的语言/话题统计
- 显示你最关注的技术栈

**判定：** ✅ 通过 / ❌ 不通过

---

### 7. 回归检查（已有功能未破坏）

- [ ] 普通书签收藏正常
- [ ] AI 自动分类正常
- [ ] 搜索正常
- [ ] 标签功能正常
- [ ] 列表功能正常

---

## 失败排查

| 现象 | 可能原因 |
|------|---------|
| 徽章不显示 | `githubProjects` 表没有对应记录 → 检查 worker 日志 |
| 项目没自动创建 | `textContent` 中没有 `github.com/owner/repo` 模式 |
| CLI 命令不存在 | 检查 `agentCmd` 是否已注册 |
| API 返回 500 | 检查 TRPC router `github.ts` 是否正确注册 |

## 验收结论

- [ ] 全部通过，可以上线
- [ ] 部分不通过（见备注）
- [ ] 严重问题，需要回滚

备注：
_____________________________
