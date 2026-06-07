# Attention

本文件是 CodeStable 技能启动必读的项目注意事项入口。所有 CodeStable 子技能开始工作前必须读取它。

## 项目碎片知识

<!-- cs-note managed: 用 cs-note 维护，新条目按下面分节追加 -->

### 编译与构建

- Monorepo：Turborepo + pnpm v11
- 安装：`pnpm install`
- 首次开发：`cp .env.sample .env` → `pnpm db:generate` → `pnpm db:migrate` → `pnpm dev`
- TypeScript 严格模式

### 运行与本地起服务

- `pnpm dev` — 启动所有 dev server（web + workers）
- `pnpm web` — 仅启动 web (Next.js)
- `pnpm workers` — 仅启动 workers
- 依赖 Docker 容器：chrome（爬虫）、meilisearch（全文搜索）

### 测试

- `pnpm test` — 运行测试
- `pnpm typecheck` — 类型检查
- `pnpm preflight` — typecheck + lint + format 一站式
- `pnpm preflight:fix` — 修复全部

### 命令与脚本陷阱

- `pnpm db:generate --name <描述>` — schema 变更后生成迁移
- `pnpm db:migrate` — 执行迁移到 SQLite
- `pnpm db:studio` — 启动 Drizzle Studio (GUI)
- `bash scripts/deploy.sh` — 一键部署到生产
- `pnpm add <pkg> --filter @karakeep/<workspace>` — 给特定 workspace 加依赖

### 路径与目录约定

- `apps/` — web, workers, browser-extension, cli, landing, mobile, mcp
- `packages/` — api, db, trpc, shared, shared-react, shared-server, sdk, e2e_tests
- 读写分离：读操作直接 SQLite，写操作通过 Liteque 队列异步处理
- 架构文档详见 `docs/internal/architecture/`

### 环境变量与凭证

- `.env` 从 `.env.sample` 复制，配置必需变量
- AI 推理通过 opencode.ai 网关调用 MiniMax M2.5

### 部署

- Docker Compose 分 3 个容器：aio（web+workers）、chrome、meilisearch
- 部署流程：`pnpm typecheck && pnpm lint:fix` → 提交推送 → CI 构建 → `bash scripts/deploy.sh`
- 详细部署信息见 `docs/internal/deployment.md`
