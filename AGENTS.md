# Karakeep — CLAUDE.md

> 本文件仅做快速入口。完整规范见 AGENTS.md（单点真理）。

## 核心命令速查

pnpm dev         — 启动所有 dev server
pnpm typecheck   — 类型检查
pnpm preflight   — typecheck + lint + format
pnpm format:fix  — 自动格式化
pnpm run db:migrate              — 执行数据库迁移
pnpm run db:generate --name 描述  — schema 变更后生成迁移
bash scripts/clean-workspace.sh --dry-run  — 预览临时文件清理
bash scripts/clean-workspace.sh --force     — 执行清理

## 清理流程（不可跳过）

bash scripts/clean-workspace.sh --dry-run  # 预览
bash scripts/clean-workspace.sh --force     # 执行
pnpm preflight                              # typecheck + lint + format
git add -A && git commit -m "..."           # 提交

详细规则见 AGENTS.md
部署守则见 AGENTS.md

---

## 项目结构快速入口

apps/     — web (Next.js), workers, browser-extension, cli, landing, mobile, mcp
packages/ — api, db, trpc, shared, shared-react, shared-server, sdk
.codestable/ — 设计文档、验收报告、架构图、决策记录
scripts/  — 部署、构建、清理自动化脚本
docker/   — Docker Compose 配置文件
