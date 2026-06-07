# Karakeep 架构总入口

> 状态：current
> 创建日期：2026-06-06

## 1. 项目简介

Karakeep（前身 Hoarder）是自托管的一站式信息收藏与管理平台。支持书签、笔记、图片、PDF 收藏，具备 AI 自动打标/摘要、全文搜索、RSS 订阅、规则引擎等能力。

## 2. 核心概念 / 术语表

| 术语 | 说明 |
|------|------|
| Bookmark | 核心实体，代表一条收藏（链接/笔记/图片/PDF） |
| Asset | 爬取资源（HTML/PDF/截图/视频） |
| Liteque | 基于 SQLite 的事务性任务队列 |
| Worker | 11 种后台任务处理器 |
| AIO | All-in-One 单容器部署模式 |

## 3. 子系统 / 模块索引

详细架构文档见 `docs/internal/architecture/`：

| 文档 | 说明 |
|------|------|
| [01-overview.md](../../docs/internal/architecture/01-overview.md) | 系统架构总览、包依赖、服务拓扑、关键设计决策 |
| [02-data-model.md](../../docs/internal/architecture/02-data-model.md) | 核心表结构、字段关系、索引策略 |
| [03-data-flow.md](../../docs/internal/architecture/03-data-flow.md) | 核心数据流（创建/搜索/导入/备份等 6 条路径） |
| [crawler/01-system.md](../../docs/internal/crawler/01-system.md) | 爬虫系统架构、并发控制、去重策略、错误处理 |

### 技术栈

- **前端**: Next.js 14 (App Router) + React + Tailwind + shadcn/ui
- **后端**: Hono + tRPC（server/client 共享类型）
- **数据库**: SQLite + Drizzle ORM + better-sqlite3
- **搜索**: MeiliSearch（全文搜索）
- **爬虫**: Playwright + Chrome（alpine-chrome:124）
- **队列**: Liteque（SQLite 存储，无 Redis）
- **AI**: OpenCode AI → MiniMax M2.5（中文优化）
- **移动端**: Expo
- **Monorepo**: Turborepo + pnpm v11

### 服务拓扑

```
karakeep-aio (s6-overlay)
├── web-server (Next.js :8001)
└── workers (Hono health :8002)
    ├─ crawler / inference / search / video
    ├─ feed / assetPreprocessing / webhook
    └─ ruleEngine / import / backup / adminMaintenance

Chrome (Playwright :9222)     MeiliSearch (:7700)
```

## 4. 关键架构决定

| 决策 | 选择 | 原因 |
|------|------|------|
| 数据库 | SQLite | 单机部署简单，无需外部服务 |
| 队列 | Liteque (SQLite) | 避免 Redis 依赖，降低运维复杂度 |
| 搜索 | MeiliSearch | 全文搜索性能好，部署简单 |
| AI | OpenCode → MiniMax | 中文推理质量好，API 兼容 OpenAI |
| 爬虫 | Playwright + Chrome | 支持 JS 渲染页面和截图 |
| AIO 模式 | s6-overlay 多进程 | 单容器部署简化运维 |

## 5. 已知约束 / 硬边界

- 2GB 内存限制：Chrome 容器限 512MB，Workers 共享进程内存
- SQLite 不适合高并发写场景
- AIO 容器内 web + workers 共享进程，单一崩溃影响全部
