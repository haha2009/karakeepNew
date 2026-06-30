# 开发工作流协议

> 原则：小步快跑，持续验证。commit 快，push 前严。

## 当前架构

- **Monorepo**: pnpm workspace + Turborepo
- **前端**: Next.js 16 (独立部署到 `/opt/karakeep/apps/web/`)
- **Workers**: tsx 直跑 TypeScript（没有编译步骤）
- **数据库**: better-sqlite3 + drizzle ORM
- **队列**: liteque (SQLite-backed, 不用 Redis)
- **部署**: SSH → deploy.sh rebuild（同时部署 web + workers）

## 循环速度

```
本地迭代:  SCP + ssh systemctl restart workers    (15秒)
验证推送:  deploy.sh rebuild                       (2分钟，含 git pull)
热修复:    deploy.sh restart  (不构建，纯重启)
```

## Workers 特殊注意事项

- Workers **没有构建步骤**，改完 .ts 直推 SCP 到服务器 → `systemctl restart karakeep-workers`
- Web 有构建步骤 (Next.js → standalone)，必须 `deploy.sh rebuild`
- 配置文件改完 `packages/shared/config.ts` → SCP 到服务器 → restart workers（零构建延迟）

## 关键约束

- **不要 git push 到生产** — 本机无 SSH 密钥 → 用 SCP 或 deploy.sh（服务器上 git pull）
- **不要删 .codestable/.specify/.superpowers** 这些是 AI 工具临时文件，已进 .gitignore
- **DATA_DIR 必须为 /var/lib/karakeep/data** — workers 和 batchRecrawl 都需要
