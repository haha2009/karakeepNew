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

## 架构规则（防止新 bug 的模式）

### AbortSignal 超时模式

- **永远用 AbortController 模式**，禁止 <code>AbortSignal.timeout()</code>
- 原因：<code>AbortSignal.timeout()</code> 创建的 signal 永久 aborted，在链式调用或循环中会级联导致所有后续操作失败
- 正确写法：<code>const ctrl = new AbortController(); const tid = setTimeout(() => ctrl.abort(), ms); try { ... } finally { clearTimeout(tid); }</code>
- 未来应抽象为 <code>packages/shared/utils/timeout.ts</code> 的 <code>withTimeout()</code>

### Deploy 完整性

- deploy.sh 必须同时管理 web + workers 两个服务
- deploy 完成后必须验证两个服务都 active
- 不要部署 web 后忘记 restart workers

### 单文件不超过 500 行

- crawlerWorker.ts 2600 行是反面教材（7 个关注点混合在一起）
- 新增逻辑时先考虑是否应该拆分到独立模块
- 合理分裂点：browser 管理、fetch 策略、解析、资源存储、限速

### Config 按领域分组

- 当前 CRAWLER_* 配置全部平铺在一级
- 新增配置时按领域分组（browser / crawl / parser / asset / video）
- 避免在 config.ts 顶部堆积 30+ 无关联的 env var

### 日志一致性

- 统一使用 <code>logger.info/warn/error</code>，不混用 <code>console</code>
- 调试日志用可搜索前缀（如 [CRAWL-DEBUG]），修复后及时清理
- 不同级别日志的含义：info=正常流程, warn=可恢复异常, error=需人工介入
