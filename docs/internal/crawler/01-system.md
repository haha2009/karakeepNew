# 爬虫系统

## 架构

```
Liteque Queue
     │
     ▼
crawlerWorker.ts
     │
     ├─ 从队列取 job (bookmarkId + URL)
     ├─ Playwright → Chrome (remote debug)
     │   └─ chrome://<chrome-container>:9222
     ├─ 爬取页面
     │   ├─ waitUntil: networkidle
     │   ├─ 提取: title, description, OG tags, favicon
     │   └─ screenshot (全页截图)
     ├─ 内容处理
     │   ├─ Readability 提取正文
     │   ├─ HTML 压缩存储
     │   ├─ 文本提取
     │   └─ PDF 生成
     ├─ 存储 resources
     │   └─ assets 表 (HTML/screenshot/PDF/text)
     ├─ 去重: contentHash (SHA256)
     └─ 完成 → 入队 inference job
```

## 并发控制

- 默认并发: 3 (可配置)
- 每个 crawler 有超时 (默认 60s)
- 失败重试: 3 次 (指数退避)
- 内存控制: Chrome 容器限制 512MB

## 去重策略

1. **URL 去重**: bookmark 创建时检查 URL hash
2. **内容去重**: assets 表通过 contentHash (SHA256) 避免存储重复内容
3. **队列去重**: Liteque 支持 job dedup

## 错误处理

| 错误类型 | 处理方式 | 重试 |
|---------|---------|------|
| Chrome 崩溃 | 等待后重试 | 3 次 |
| 超时 | 跳过，标记 failed | 1 次 |
| DNS 解析失败 | 标记 unreachable | 不重试 |
| 403/404 | 标记 unreachable | 不重试 |
| 内容过短 | 标记 lowQuality | 不重试 |

## 内容类型

- **普通网页**: Playwright 加载 → Readability 提取
- **PDF**: 直接下载
- **图片**: 直接下载
- **视频**: 存元数据，视频处理由 videoWorker 处理
- **RSS**: feedWorker 处理
- **Twitter/YouTube**: 特殊提取器

## 内存考量 (2GB RAM)

- Workers 共享 Node.js 进程内存
- Chrome 单独容器，可独立限制
- 大页面 (DOM 节点 > 5000) 自动截断
- 截图分辨率限制 1280x720
- PDF 生成限制 10 页

## 调试

```bash
# 查看 Chrome 调试端口 (docker 环境)
docker compose exec chrome chromium-browser --remote-debugging-port=9222

# 单独测试爬取
pnpm --filter @karakeep/workers run start

# 查看 worker 日志
docker compose logs karakeep-aio | grep crawler
```
