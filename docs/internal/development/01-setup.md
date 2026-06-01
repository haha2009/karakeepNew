# 开发环境搭建

## 前置依赖

- **Node.js**: >= 20
- **pnpm**: >= 11 (corepack enable && pnpm setup)
- **Docker**: (用于 Chrome 爬虫 + MeiliSearch)
- **Git**

## 克隆与安装

```bash
git clone <repo-url>
cd karakeep
pnpm install
```

## 环境变量

```bash
cp .env.example .env
```

必需配置项:
- `NEXTAUTH_SECRET` — 任意随机字符串
- `NEXTAUTH_URL` — `http://localhost:3000`
- `MEILI_MASTER_KEY` — MeiliSearch key
- `OPENAI_BASE_URL` — `https://opencode.ai/v1` (或其他兼容 API)
- `OPENAI_API_KEY` — API key

可选配置项:
- `DATABASE_URL` — SQLite 路径 (默认 `data/karakeep.db`)
- `CHROME_URL` — Chrome remote debug URL

## 启动数据库

```bash
pnpm db:generate   # 生成迁移文件
pnpm db:migrate    # 执行迁移 (创建 SQLite 表)
```

## 启动开发环境

```bash
# 终端 1: 启动 web (Next.js)
pnpm web

# 终端 2: 启动 workers (爬虫/推理等)
pnpm workers

# 或者一起启动 (资源消耗大)
pnpm dev
```

## 验证

访问 `http://localhost:3000` → 注册账号 → 添加一个链接测试爬取

## 常见问题

- **SQLite 权限错误**: 确保 `data/` 目录存在且可写
- **Chrome 连接失败**: 检查 `CHROME_URL` 配置，确保 Chrome 容器运行
- **MeiliSearch key 不匹配**: 清空 meili 数据目录重新启动
- **pnpm 版本问题**: `corepack enable && corepack prepare pnpm@11 --activate`
