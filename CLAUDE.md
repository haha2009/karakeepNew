# Karakeep — CLAUDE.md

> 本文件仅做快速入口。完整规范见 AGENTS.md（单点真理）。

## 当前环境

- **版本**: v0.x (Monorepo, pnpm + Turborepo, tsx 直跑 TS)
- **模型**: Claude Opus 4.6 (CLI 模式)
- **数据目录**: `/var/lib/karakeep/data/` (生产) — 必保护，删除 = 数据丢失
- **代码仓库 (本地)**: `/Users/claw/Projects/test/karakeep/`
- **代码仓库 (服务器)**: `/home/ubuntu/src/`

## 硬性约束

- **部署方式**: systemd + deploy.sh，不用 Docker / Dokku 部署 karakeep 本身
- **Git 推送**: 本机可能无 SSH 密钥 → **优先 SCP 部署**，不是 `git push`
- **Workers**: 用 tsx 直跑 TypeScript，没有编译步骤，改完 SCP + restart 即可
- **生产目录**: `/opt/karakeep/apps/web/` = 临时构建产物，随时可重建
- **代码仓库**: `/home/ubuntu/src/` = 唯一持久化源码（含 git history）

## 服务拓扑

```
124.222.143.123 (Ubuntu + systemd)
├── karakeep      (systemd, Next.js standalone @ :3000)
├── karakeep-workers (systemd, tsx index.ts)
├── Meilisearch   (Docker @ :7700)
└── freellmapi    (Docker @ :3001, dokku managed)
```

## 核心命令速查（本地）

pnpm dev         — 启动所有 dev server
pnpm typecheck   — 类型检查
pnpm preflight   — typecheck + lint + format
pnpm format:fix  — 自动格式化
bash scripts/clean-workspace.sh --dry-run  — 预览清理
bash scripts/clean-workspace.sh --force     — 执行清理

## 部署命令（生产 SSH 124.222.143.123）

```bash
# 一键部署（含自动备份，同时部署 web + workers）
ssh ubuntu@124.222.143.123 /home/ubuntu/deploy.sh rebuild

# 健康快照（5 秒全局图）
ssh ubuntu@124.222.143.123 /home/ubuntu/health.sh

# 单独重启（workers 改代码后不需要 rebuild）
ssh ubuntu@124.222.143.123 /home/ubuntu/deploy.sh restart
# 或直接:
ssh ubuntu@124.222.143.123 "sudo systemctl restart karakeep-workers"

# 查看状态
ssh ubuntu@124.222.143.123 /home/ubuntu/deploy.sh status

# 回滚
ssh ubuntu@124.222.143.123 /home/ubuntu/deploy.sh rollback <commit>

# 查日志
ssh ubuntu@124.222.143.123 /home/ubuntu/deploy.sh logs

# ⚠️ 本机 git push 可能失败（SSH 密钥问题）→ 用 SCP
scp <file> ubuntu@124.222.143.123:/home/ubuntu/src/<path>
```

## 生产调试命令

```bash
# 批量补爬失败书签
ssh ubuntu@124.222.143.123
cd /home/ubuntu/src/apps/workers
DATA_DIR=/var/lib/karakeep/data /home/ubuntu/src/node_modules/.bin/tsx scripts/batchRecrawl.ts failure --limit=30

# 查 SQLite
ssh ubuntu@124.222.143.123 "sqlite3 /var/lib/karakeep/data/db.db 'SELECT ...'"

# 查爬虫失败
ssh ubuntu@124.222.143.123 "sudo journalctl -u karakeep-workers --grep='Crawling job failed' --since '1 hour ago'"
```

## 清理流程

bash scripts/clean-workspace.sh --dry-run  # 预览
bash scripts/clean-workspace.sh --force     # 执行
pnpm preflight                              # 检查
git add -A && git commit -m "..."           # 提交

详细规范见 AGENTS.md，部署详情见 `.claude/deployment.md`，开发手册见 `.claude/dev-workflow.md`。
