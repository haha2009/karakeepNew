# Karakeep — CLAUDE.md

> 本文件仅做快速入口。完整规范见 AGENTS.md（单点真理）。

## 硬性约束

- **部署方式**: systemd + deploy.sh，不用 Docker / Dokku 部署 karakeep 本身
- **数据目录**: `/var/lib/karakeep/data/` 必保护，删除 = 数据丢失
- **生产目录**: `/opt/karakeep/apps/web/` = 临时构建产物，随时可重建
- **代码仓库**: `/home/ubuntu/src/` = 唯一持久化源码（含 git history）

## 核心命令速查（本地）

pnpm dev         — 启动所有 dev server
pnpm typecheck   — 类型检查
pnpm preflight   — typecheck + lint + format
pnpm format:fix  — 自动格式化
bash scripts/clean-workspace.sh --dry-run  — 预览清理
bash scripts/clean-workspace.sh --force     — 执行清理

## 服务器运维（SSH 124.222.143.123）

```bash
# 一键部署（含自动备份）
ssh ubuntu@124.222.143.123 /home/ubuntu/deploy.sh rebuild

# 健康快照（5 秒全局图）
ssh ubuntu@124.222.143.123 /home/ubuntu/health.sh

# 单命令
ssh ubuntu@124.222.143.123 /home/ubuntu/deploy.sh {help|restart|rollback <commit>|status|backup|logs}
```

## 清理流程

bash scripts/clean-workspace.sh --dry-run  # 预览
bash scripts/clean-workspace.sh --force     # 执行
pnpm preflight                              # 检查
git add -A && git commit -m "..."           # 提交

详细规范见 AGENTS.md，部署详情见 `.claude/deployment.md`。
