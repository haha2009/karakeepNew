# Karakeep

一站式信息收藏与管理平台。Monorepo (Turborepo + pnpm)。

## 工作流

```
你提需求 → Agent拆任务(todowrite) → 逐个开发/提交
  → typecheck+lint → 推main → CI构建镜像
  → Agent通知"准备好了" → 你说"上线"
  → bash scripts/deploy.sh → 健康检查通过 → 完成
```

### 流程说明

| 阶段 | 你做 | Agent做 |
|------|------|---------|
| 需求 | 描述你要什么 | 拆成具体任务，写入 todowrite |
| 开发 | 配合确认 | 逐个实现任务，每次提交过 pre-commit |
| 验证 | — | `pnpm typecheck && pnpm lint` 确保质量 |
| 上线 | 说"上线" | 执行 `bash scripts/deploy.sh`，验证 HTTP 200 |

### 自我进化

每次上线后，Agent 自动评估工作流哪里卡顿，更新本文档。流程是活的，用着不顺就改。

## 快速入口

- **架构文档** → [docs/internal/architecture/](docs/internal/architecture/)
- **开发指南** → [docs/internal/development/](docs/internal/setup/)
- **规范标准** → [docs/internal/standards/](docs/internal/standards/)
- **爬虫系统** → [docs/internal/crawler/](docs/internal/crawler/)
- **产品文档** → [docs/internal/product/](docs/internal/product/)
- **Agent 速查** → [.claude/brief.md](.claude/brief.md)
- **部署纪要** → [.claude/deployment.md](.claude/deployment.md)

## 核心命令

| 命令 | 用途 |
|------|------|
| `pnpm dev` | 启动开发环境 |
| `pnpm typecheck` | 类型检查 |
| `pnpm test` | 运行测试 |
| `pnpm lint:fix` | 自动修复 lint |
| `pnpm format:fix` | 自动格式化 |
| `pnpm db:generate --name <desc>` | 数据库迁移 |
| `bash scripts/deploy.sh` | 一键部署到生产 |
