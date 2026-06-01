# Karakeep

一站式信息收藏与管理平台。Monorepo (Turborepo + pnpm)。

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

> 首次接触？先读 `.claude/brief.md` (2 分钟)，再根据需要查阅详细文档。
