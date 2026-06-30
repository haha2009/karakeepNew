# Karakeep — Agent 规范

> **单点真理**：本文件是所有 Agent 行为的最高准则。

## 当前版本信息

- **版本**: v0.x (Monorepo, pnpm + Turborepo)
- **模型**: Claude Opus 4.6 (CLI 模式)
- **开发模式**: 系统 prompt 中通过 skill 注入行为约束
- **数据目录**: `/var/lib/karakeep/data/` (生产) — 必保护

## Agent 守则（所有 Agent 必须遵守）

### 核心理念

**你只做两件事：提需求 + 验收，其余 Agent 干。**

### 第一原则：先读后写

- 编辑文件前必须先读取。
- 用 file-picker / code-searcher / read_files 获取上下文。
- 修改导出符号后，必须更新所有引用。

### 第二原则：质量优先

- 优先正确性。每次改动后 spawn code-reviewer-deepseek-flash。
- typecheck 是底线——不通过不提交。

### 第三原则：最小改动

- 只改用户要求的内容，不顺手优化未涉及的部分。

### 第四原则：不擅自动线上

- 严禁擅自推送到线上。必须用户明确同意并主动触发。

---

## 🚨 生产踩坑教训（血泪经验，必须遵守）

### 1. Workers 服务必须随 Web 一起部署

`deploy.sh rebuild` 同时重启 `karakeep` + `karakeep-workers`。只改 workers 代码时也记得重启 workers 服务：
```bash
ssh ubuntu@124.222.143.123 "sudo systemctl restart karakeep-workers"
```

### 2. GitHub SSH Push 可能不可用

本机 SSH 密钥可能没有 GitHub push 权限（ Connection closed by UNKNOWN port 65535）。
**不要依赖 `git push` 部署到生产** → 直接用 SCP 同步文件到服务器：
```bash
scp <file> ubuntu@124.222.143.123:/home/ubuntu/src/<path>
```

### 3. Workers 用 tsx 直接跑 TS，不改代码只需重启

```
/home/ubuntu/src/node_modules/.bin/tsx index.ts
```
workers 没有编译步骤，改完 .ts 直推 SCP + systemctl restart 即可。

### 4. 不要提交 AI 工具临时文件

以下目录**绝不能进入 git**（已在 .gitignore 中，但如果已经跟踪则需要手动清理）：
- `.codestable/` — AI 设计工具工作区
- `.specify/` — spec-kit 工具
- `.superpowers/` — superpowers 方法论工具
- `debug-*.js`, `*.log` — 调试残留

如果发现这些文件被跟踪：
```bash
git rm -r --cached .codestable/ .specify/ .superpowers/
git commit -m "chore: remove AI tooling artifacts"
```

### 5. 批量补爬脚本

```bash
ssh ubuntu@124.222.143.123
cd /home/ubuntu/src/apps/workers
DATA_DIR=/var/lib/karakeep/data /home/ubuntu/src/node_modules/.bin/tsx scripts/batchRecrawl.ts failure --limit=30
```
`DATA_DIR` 必须设置，否则找不到数据库。

### 6. AbortSignal 级联故障

`AbortSignal.timeout()` 创建的 signal 一旦触发，会永久 abort。xliteque 在 job 超时时 abort controller → 影响后续所有操作。
**永远用 AbortController + setTimeout + clearTimeout 模式管理超时。**

### 7. data URI 图片不能过滤

`imageUrl.startsWith("data:")` → 不要过滤！浏览器原生支持 data URI `<img src="data:image/...">`。
之前的 bug 就是误判 data URI 为"无效图片"而写入 null。

### 8. tsx 在 systemd 中找不到

systemd 的 PATH 可能不包含 `node_modules/.bin`。 workers 代码中已用 `createRequire + require.resolve("tsx/package.json")` 在运行时定位绝对路径。

---

## 提交前清理（不可跳过）

每次 commit 前必须先清理工作区。

### 清理流程

1. bash scripts/clean-workspace.sh --dry-run  — 预览
2. bash scripts/clean-workspace.sh --force     — 执行
3. pnpm preflight                              — typecheck+lint+format
4. git add -A                                  — 暂存
5. git commit -m "..."                         — 提交

### 清理范围

- 备份文件: *.bak, *.bak2, *.backup, *.new, *.working, *.template
- 临时文档: ACCEPTANCE_*.md, FINAL_*.md, TASK_*.md, *_CHECKLIST.md 等
- 临时 JSON: *-todos*.json, mark-*.json, complete-*.json 等
- 一次性 .sh: 白名单 start-dev.sh, do-build.sh, karakeep-linux.sh
- 异常目录: 单引号或空格开头
- **AI 工具临时文件**: `.codestable/`, `.specify/`, `.superpowers/`
- **Git 状态**: 确认 `git status --short` 干净再 push

### 安全规则（永不删除）

1. Git 跟踪的文件
2. 白名单中的文件
3. 受管目录中的正规产物 (scripts/, docs/, docker/)
4. .gitignore 排除的目录
5. **生产数据**: `/var/lib/karakeep/data/` 下的所有文件

---

## Commit 前检查清单

1. git status --short （确认工作区干净）
2. scripts/clean-workspace.sh --force （清理临时文件）
3. pnpm preflight （typecheck + lint + format 通过）
4. git add -A && git commit -m "..." （提交）

---

## 核心命令

### 本地
```
pnpm dev             — 启动所有 dev server
pnpm typecheck       — 类型检查
pnpm preflight       — typecheck + lint + format
pnpm format:fix      — 自动格式化
bash scripts/clean-workspace.sh --dry-run  — 预览清理
bash scripts/clean-workspace.sh --force     — 执行清理
```

### 生产部署 (SSH 124.222.143.123)
```
# 一键部署（含自动备份）
ssh ubuntu@124.222.143.123 /home/ubuntu/deploy.sh rebuild

# 健康快照
ssh ubuntu@124.222.143.123 /home/ubuntu/health.sh

# 查看状态
ssh ubuntu@124.222.143.123 /home/ubuntu/deploy.sh status

# 单独重启 workers（改 workers 代码后）
ssh ubuntu@124.222.143.123 "sudo systemctl restart karakeep-workers"

# 查日志
ssh ubuntu@124.222.143.123 /home/ubuntu/deploy.sh logs
ssh ubuntu@124.222.143.123 "sudo journalctl -u karakeep-workers --since '10 min ago'"

# 回滚
ssh ubuntu@124.222.143.123 /home/ubuntu/deploy.sh rollback <commit>
```

### 生产调试
```bash
# 批量补爬失败的书签
ssh ubuntu@124.222.143.123
cd /home/ubuntu/src/apps/workers
DATA_DIR=/var/lib/karakeep/data /home/ubuntu/src/node_modules/.bin/tsx scripts/batchRecrawl.ts failure --limit=30

# 查看 SQLite 数据库
ssh ubuntu@124.222.143.123 "sqlite3 /var/lib/karakeep/data/db.db 'SELECT ...'"

# 查爬取失败原因
ssh ubuntu@124.222.143.123 "sudo journalctl -u karakeep-workers --grep='Crawling job failed' --since '1 hour ago'"
```

---

## 项目结构概览

### Monorepo 包

| 包 | 路径 | 职责 |
|----|------|------|
| @karakeep/web | apps/web | Next.js Web 前端（独立部署） |
| @karakeep/workers | apps/workers | 后台 worker（爬虫、推理、搜索等） |
| @karakeep/db | packages/db | Drizzle ORM + SQLite schema |
| @karakeep/shared | packages/shared | 共享类型、配置、工具函数 |
| @karakeep/shared-server | packages/shared-server | 服务端共享（队列、推理客户端） |
| @karakeep/shared-react | packages/shared-react | React hooks（tRPC） |

### Worker 类型

| Worker | 职责 |
|--------|------|
| crawler | 爬取网页 → 提取标题/描述/图片 |
| inference | AI 推理（标签、摘要、GitHub分析） |
| search | 搜索索引 |
| lowPriorityCrawler | 低优先级补爬队列 |
| assetPreprocessing | 图片/PDF 后处理 |
| githubDeepDive | GitHub 项目深度分析 |

### 部署拓扑

```
/home/ubuntu/src/                    ← git 仓库 + node_modules + 构建缓存
├── apps/web/.next/standalone/       ← Next.js 构建产物
├── apps/workers/                    ← workers 源码（tsx 直跑 TS）
├── node_modules/                    ← 2.3GB（唯一副本）

/opt/karakeep/apps/web/              ← 生产运行时 (180MB, symlink)
└── server.js                        ← Next.js 唯一入口

/var/lib/karakeep/data/              ← 运行时数据（SQLite + assets）
```

### 关键文件

| 文件 | 用途 |
|------|------|
| deploy.sh | 一键部署脚本（web + workers） |
| health.sh | 服务健康快照 |
| .claude/deployment.md | 部署详细纪要 |
| .claude/dev-workflow.md | 开发工作流协议 |
