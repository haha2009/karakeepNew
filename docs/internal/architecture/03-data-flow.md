# 核心数据流

## 1. 创建链接 → 爬取 → 推理 → 索引

```
用户添加链接
     │
     ▼
Web UI → tRPC bookmarks.create
     │
     ├─ 写 SQLite (bookmarks 行)
     ├─ 返回给用户 (立即看到标题/URL)
     └─ Liteque 入队 crawler job
           │
           ▼
     crawlerWorker
     ├─ Playwright → Chrome → 获取页面
     ├─ 提取: title, description, content, image, favicon
     ├─ 生成 screenshot + PDF
     ├─ 存储 assets (HTML/screenshot/PDF)
     ├─ 更新 bookmark 行
     └─ Liteque 入队 inference job
           │
           ▼
     inferenceWorker
     ├─ 调用 OpenCode AI (MiniMax M2.5)
     ├─ 生成: summary, tags (AI 自动打标)
     ├─ 更新 bookmark (summary)
     ├─ 创建 tag + bookmark_tags (aiAttached=true)
     └─ Liteque 入队 search indexing job
           │
           ▼
     searchIndexingWorker
     └─ MeiliSearch: 添加/更新文档
```

## 2. 全文搜索

```
用户搜索
     │
     ▼
Web UI → tRPC search.search
     │
     ├─ MeiliSearch: search(index, query, filters)
     │   └─ 条件: userId, status, tags, list, date range
     │
     └─ 返回: 匹配的 bookmark id 列表
           │
           ▼
     tRPC bookmarks.getByIds (批量查询 SQLite)
     └─ 返回完整 bookmark 数据给前端
```

## 3. RSS Feed 导入

```
feedWorker (定时轮询)
     │
     ├─ 读 feeds 表 → 检查是否需要刷新
     ├─ RSS 解析器 → 提取新条目
     ├─ 对每个新条目:
     │   ├─ 检查是否已存在 (URL 去重)
     │   ├─ 创建 bookmark
     │   └─ 入队 crawler job
     └─ 更新 feed.lastRefreshedAt
```

## 4. 规则引擎

```
创建/更新 bookmark 后
     │
     ▼
ruleEngineWorker
     ├─ 读取启用中的 rules (按 userId 分组)
     ├─ 对每个 rule:
     │   ├─ 匹配 conditions (tag/domain/status/keyword)
     │   └─ 执行 actions (add tag / archive / favourite)
     └─ 记录执行历史
```

## 5. 数据导入

```
importWorker
     │
     ├─ 支持格式: HTML bookmarks export, Pocket JSON, 等
     ├─ 逐条导入 bookmark
     ├─ 去重 (URL hash)
     └─ 入队 crawler job (可选)
```

## 6. 备份

```
backupWorker
     └─ SQLite dump → 压缩 → 存储到 volumes
```

## 关键要点

- **读写分离**: 用户操作立即写 SQLite 返回，异步任务通过 Liteque 队列处理
- **去重**: assets 表用 contentHash 去重；bookmark 创建时用 URL hash 检查重复
- **错误处理**: crawler/inference 失败会重试，达上限后标记失败状态
- **队列**: Liteque 基于 SQLite 的事务性队列，保证 at-least-once delivery
