# AI 自动分类 + 摘要 + 标签（一次搞定）

## 概述

收藏任意书签 → 爬取完成后 → AI 一次调用完成三件事并自动归类到用户已有的文件夹。

## 用户流程

```
用户收藏书签（任意来源）
       ↓
爬取完成（已有）
       ↓
AI 一次调用 → 写入摘要 → 关联标签 → 添加到文件夹
       ↓
书签卡片直接显示摘要 + 标签 + 所属文件夹
```

## 设计细节

### 1. Schema 变更

**`bookmarks` 表新增字段：**

```typescript
classificationStatus: text("classificationStatus", {
  enum: ["pending", "failure", "success"],
}).default("pending"),
```

### 2. Queue 变更

**`zOpenAIRequestSchema` 扩展 type：**

```typescript
type: z.enum(["summarize", "tag", "classify"]).default("classify"),
```

### 3. 新增 classify.ts

在 `apps/workers/workers/inference/classify.ts` 中实现 `runClassify()`：

```
fetchBookmarkDetails(bookmarkId)
  → bookmark info (title, url, description, content)
  → user's all manual lists (with full path: "Ai/MCP")

buildPrompt(bookmark, userLists)
  → System: "用户有以下文件夹层级：{folderHierarchy}。分析书签，返回 JSON"
  → User: bookmark content (truncated to context limit)

call AI with structured output:
  {
    summary: string,
    tags: string[],
    targetFolder: string | null  // 完整路径如 "Ai/MCP"，null 表示无合适文件夹
  }

write summary to bookmarks.summary
connectTags(bookmarkId, tags, userId)  // 复用现有函数
if targetFolder:
  resolve listId from folder path
  add bookmark to list via Bookmark.addToList()
```

**关键实现点：**
- 一次 AI 调用替代当前的 tag + summarize 两次调用
- 复用 `connectTags()` 处理标签关联
- 复用 `triggerSearchReindex()` 更新搜索索引
- 复用 `WebhooksService.triggerWebhook()` 触发 webhook
- 复用 `RuleEngine.triggerOnEvent()` 触发规则引擎

### 4. Crawler 变更

**`apps/workers/workers/crawlerWorker.ts` 中替换：**

```typescript
// 之前（两次调用）：
await OpenAIQueue.enqueue({ bookmarkId, type: "tag" });
await OpenAIQueue.enqueue({ bookmarkId, type: "summarize" });

// 之后（一次调用）：
await OpenAIQueue.enqueue({ bookmarkId, type: "classify" });
```

### 5. InferenceWorker 变更

**`apps/workers/workers/inference/inferenceWorker.ts` 中新增 case：**

```typescript
switch (request.data.type) {
  case "summarize": await runSummarization(...); break;
  case "tag": await runTagging(...); break;
  case "classify": await runClassify(...); break;  // 新增
}
```

status 标记也相应扩展：

```typescript
...(request.type === "classify" ? { classificationStatus: status } : {})
```

### 6. 其他入队点变更

三处启动推理的地方全部替换 tag + summarize 为 classify：

| 位置 | 类型 | 当前 |
|------|------|------|
| `crawlerWorker.ts:2487` | LINK | `tag` + `summarize` |
| `assetPreprocessingWorker.ts:464` | ASSET | `tag` + `summarize` |
| `bookmarks.ts:410` | TEXT | `tag` |

统一替换为 `classify`。TEXT 书签当前仅有 tag，classify 替换后也会自动获得摘要（因为 classify 一次性完成三件事）。

### 7. Admin re-enqueue

admin 路由 (`admin.ts:320,728,761`) 中的重新推理也改为 `classify`。

### 8. 文件夹分配实现（Worker 上下文）

Worker 中没有 TRPC auth context，不能直接调用 `ManualList.addBookmark()`。改为直接操作 DB：

```typescript
// classify.ts 中
const matchedList = await db.query.bookmarkLists.findFirst({
  where: and(
    eq(bookmarkLists.userId, userId),
    eq(bookmarkLists.type, "manual"),
    eq(bookmarkLists.name, folderName),  // 匹配末级文件夹名
  ),
  with: { parent: true }  // 必要时递归
});

if (matchedList) {
  await db.insert(bookmarksInLists).values({
    listId: matchedList.id,
    bookmarkId,
  }).onConflictDoNothing();
  
  // 触发规则引擎
  await RuleEngine.triggerOnEvent(userId, bookmarkId, [
    { type: "addedToList", listId: matchedList.id },
  ]);
}
```

文件夹路径匹配策略：
- AI 返回 `"Ai/MCP"` → 解析为 `["Ai", "MCP"]`
- 从 root 开始逐层匹配 `name + parentId`
- 如果找不到，降级到只匹配末级文件夹名 `"MCP"`

## AI Prompt 设计

```
## 用户文件夹结构

{所有 manual lists 以 tree 格式列出}

## 书签内容

URL: {url}
标题: {title}
描述: {description}
正文内容: {content (truncated)}

## 要求

分析这个书签，返回 JSON:
{
  "summary": "一句话简介",
  "tags": ["标签1", "标签2", ...],
  "targetFolder": "Ai/xxx" | null
}

- summary: 中文，不超过 100 字，直白说明这个书签是什么
- tags: 3-5 个，英文小写，用连字符分隔，反映语言/用途/领域
- targetFolder: 从用户文件夹中选择最合适的，路径用 / 分隔，
  null 表示没有合适的文件夹
```

## 文件夹层级获取

查询用户的 `bookmarkLists` 表：
- 只取 `type === "manual"` 的列表
- 通过 `parentId` 递归构建树形结构
- 生成层级路径：`"Ai/MCP"`, `"Ai/Agent"`, `"Design/UI"`

## 向后兼容

- `enableAutoTagging` 和 `enableAutoSummarization` 配置保留
- 新增 `enableAutoClassify` 配置（默认 true）
- 如果 classify 被禁用，回退到现有的 tag + summarize 行为
- 已有书签不受影响（只处理新收藏的）
