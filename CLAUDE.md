# Karakeep — CLAUDE.md

> 本文件仅做快速入口。完整规范见 AGENTS.md（单点真理）。

## 核心命令速查

pnpm dev         — 启动所有 dev server
pnpm typecheck   — 类型检查
pnpm preflight   — typecheck + lint + format
pnpm format:fix  — 自动格式化
bash scripts/clean-workspace.sh --dry-run  — 预览清理
bash scripts/clean-workspace.sh --force     — 执行清理

## 清理流程

bash scripts/clean-workspace.sh --dry-run  # 预览
bash scripts/clean-workspace.sh --force     # 执行
pnpm preflight                              # 检查
git add -A && git commit -m "..."           # 提交

详细规范见 AGENTS.md
