# 腾讯云部署纪要

## 环境

- **服务器**: 腾讯云轻量云 124.222.143.123 (2GB RAM, 1核)
- **系统**: Ubuntu
- **用户**: ubuntu
- **项目代码**: `/Users/claw/Projects/test/karakeep/`
- **部署路径**: `/home/ubuntu/karakeep/docker-compose.yml`

## 服务拓扑

```
docker-compose.yml
├── web         (karakeep-custom:latest, s6 + Hono)
│   ├── init-db-migration   (node /db_migrations/index.js)
│   ├── svc-web             (Next.js @ :3000)
│   └── svc-workers         (后台 worker)
├── chrome      (karakeep-chrome:local, Playwright 爬虫)
└── meilisearch (getmeili/meilisearch:v1.41.0, 全文搜索 @ :7700)
```

- 暴露端口: 3000 (web)，其余仅内网
- NEXTAUTH_URL: `http://124.222.143.123:3000`
- AI 模型: deepseek-v4-pro (inference), 通过 opencode.ai 网关
- 数据库: SQLite (docker volume)

## CI 策略 (2026-06-03 优化)

| 触发 | 构建内容 | 耗时 |
|------|---------|------|
| `push main` / `workflow_dispatch` | 仅 `aio` × `linux/amd64` | ~12min |
| `release` | 全部 5 镜像 × 2 架构 (web/workers/cli/mcp/aio + amd64/arm64) | ~40min |

> 日常 push 放弃 arm64（服务器是 x86），放弃 web/workers/cli/mcp 独立镜像（只用 aio 部署），CI 时间从 40min→12min。

> **CI Billing 技巧**: 免费分钟耗尽后，切 repo 为 public → 触发 `workflow_dispatch` → CI 跑完 → 切回 private。每次大约消耗 7-10 分钟（aio/amd64）。

## 部署流程

### 正常流程 (ghcr.io)
```bash
ssh ubuntu@124.222.143.123
cd /home/ubuntu/karakeep
docker compose pull web
docker compose up -d --no-deps --force-recreate web
```

### 中国网络备选 (Mac pull + SCP docker load)
当 ghcr.io 下载慢时:
```bash
# Mac: 从 ghcr 拉取最新 amd64 镜像（CI 构建的 aio 镜像）
docker pull --platform linux/amd64 ghcr.io/haha2009/karakeepnew/karakeep:latest-amd64

# Mac: 保存为 tar（单架构镜像无 manifest bug，无需修复）
docker save ghcr.io/haha2009/karakeepnew/karakeep:latest-amd64 | gzip > /tmp/karakeep-latest.tar.gz

# Mac: SCP 到服务器
scp /tmp/karakeep-latest.tar.gz ubuntu@124.222.143.123:/home/ubuntu/

# 服务器: 加载并替换
ssh ubuntu@124.222.143.123 '
  gunzip -c /home/ubuntu/karakeep-latest.tar.gz | docker load
  docker tag ghcr.io/haha2009/karakeepnew/karakeep:latest-amd64 karakeep-custom:latest
  cd /home/ubuntu/karakeep && docker compose up -d --no-deps --force-recreate web
  rm /home/ubuntu/karakeep-latest.tar.gz
'
```

> 注意：单架构（仅 amd64）的 `docker save` 没有 multi-arch manifest bug，`docker load` 可以直接工作，无需修复脚本。

### 热修复 (docker exec + commit)
```bash
# 修补运行中容器的文件
docker exec <container> sed -i 's/old/new/' /path/to/file
# 提交为新镜像
docker commit <container> karakeep-custom:latest
# 切换 compose 到本地镜像
sed -i 's|image: ghcr.io/.*|image: karakeep-custom:latest|' docker-compose.yml
docker compose up -d --no-deps --force-recreate web
```

## 代理 (Proxy) 配置

绕过 GFW，让爬虫能抓取 x.com/Twitter 等被墙站点。

| 组件 | 配置 |
|------|------|
| **代理服务** | sing-box 容器 (`karakeep-proxy-1`)，监听 `0.0.0.0:1080` |
| **协议** | Hysteria2 → HK01 (香港)，16 个 CF VLESS 节点作为 urltest 备用 |
| **配置文件** | `/home/ubuntu/sing-box/config.json` |
| **爬虫环境变量** | `CRAWLER_HTTP_PROXY=http://127.0.0.1:1080` (web 容器) |
| **订阅源** | 主: `api.jfcs.site`, 备: `edgetunnel-51k.pages.dev` |

> `network_mode: "host"` 下，容器间通过 `127.0.0.1:1080` 直接访问代理。

## 备份

- crontab: 每日 3:00 AM 自动备份
- 备份内容: SQLite 数据库（docker volume `data`）
- 保留策略: 7 天
- 路径: `/home/ubuntu/backups/`
- 脚本: `/home/ubuntu/karakeep/backup.sh`

## 已知问题

| 问题 | 修复 |
|------|------|
| ghcr.io 中国下载极慢 (~1-2MB/min) | 备选: Mac pull → SCP → docker load |
| `docker save` multi-arch manifest bug | 需用脚本修复 manifest.json (见上) |
| CI cache-from 复用旧层 | 加 `CACHE_BUSTER=${{ github.run_id }}` build arg |
| CI typecheck OOM | 不影响 Docker 构建，忽略 |
| 服务器 2GB 内存限制 | Chrome 爬虫 + Node 双引擎，OOM 时降级 chrome |
| GitHub Actions 免费分钟耗尽 | 切 public → 触发 workflow_dispatch → 成功后切回 private |
| `gh` CLI 401 "Bad credentials" | `GH_TOKEN` 环境变量覆盖 keyring 认证，需 `unset GH_TOKEN` |
| x.com/Twitter 被 GFW 封锁 | 部署 sing-box 代理容器，`CRAWLER_HTTP_PROXY=http://127.0.0.1:1080` |

## 内存限制 (2GB 关键约束)

| 服务 | 建议限制 | 说明 |
|------|---------|------|
| chrome | 512MB | 爬虫内存大户 |
| meilisearch | 256MB | 索引不要太大 |
| web (Node) | 1GB | web + workers 共享 |
| 系统 | 余量 | 约 256MB |

## 注意事项

- mirror 使用: apt 用 tsinghua, npm 用 npmmirror, pip 用 tsinghua
- yt-dlp 预下载在 docker 镜像中
- AI 请求通过 opencode.ai 网关，需保持网络连通
- 数据持久化在 docker volumes，定期备份
