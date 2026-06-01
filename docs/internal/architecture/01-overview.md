# 系统架构总览

## 包依赖关系

```
apps/web ──── packages/trpc ──── packages/db ─── SQLite
                    │
apps/workers ───────┤
                    ├──── packages/shared
apps/cli            ├──── packages/shared-server
apps/mcp            ├──── packages/shared-react
apps/mobile         ├──── packages/api
apps/landing        ├──── packages/sdk
                    └──── packages/open-api
```

## 服务架构 (Docker)

```
┌─────────────────────────────────────────────────────┐
│                  karakeep-aio (s6-overlay)           │
│  ┌──────────────┐  ┌──────────────────────────────┐  │
│  │  web-server   │  │  workers (Hono health :8002)│  │
│  │  (Next.js     │  │  ├─ crawler                 │  │
│  │   :8001)      │  │  ├─ inference               │  │
│  │               │  │  ├─ search                  │  │
│  └──────┬───────┘  │  ├─ video                   │  │
│         │          │  ├─ feed                    │  │
│         │          │  ├─ assetPreprocessing       │  │
│         │          │  ├─ webhook                 │  │
│         │          │  ├─ ruleEngine              │  │
│         │          │  ├─ import                  │  │
│         │          │  ├─ backup                  │  │
│         │          │  └─ adminMaintenance        │  │
│         │          └──────────────────────────────┘  │
└─────────┼───────────────────────────────────────────┘
          │ HTTP (tRPC)
          ▼
┌──────────────────┐   ┌──────────────────┐
│   Chrome          │   │   MeiliSearch    │
│   (Playwright)    │   │   (搜索 :7700)    │
└──────────────────┘   └──────────────────┘
```

## 关键设计决策

| 决策 | 选择 | 原因 |
|------|------|------|
| 数据库 | SQLite | 单机部署简单，无需外部服务 |
| 队列 | Liteque (SQLite) | 避免 Redis 依赖，降低运维复杂度 |
| 搜索 | MeiliSearch | 全文搜索性能好，部署简单 |
| AI | OpenCode → MiniMax | 中文推理质量好，API 兼容 OpenAI |
| 爬虫 | Playwright + Chrome | 支持 JS 渲染页面，截图 |
| AIO 模式 | s6-overlay 多进程 | 单容器部署简化运维 |

## 端口映射

| 端口 | 服务 | 暴露 |
|------|------|------|
| 8001 | Web (Next.js) | 对外 |
| 8002 | Workers health | 内网 |
| 7700 | MeiliSearch | 内网 |
| 9222 | Chrome debug | 内网 |
