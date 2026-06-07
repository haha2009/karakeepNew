# Karakeep AI 助手

## 概述

在 karakeep 中嵌入 AI 助手，支持两种交互方式：
1. **内置聊天侧边栏** — 在 karakeep 界面右侧对话，基于收藏内容回答问题
2. **MCP Server** — 供外部 AI 客户端（Claude Desktop、Cline 等）连接，新增权限分级

## 架构

```
┌──────────────────────────────────────────────┐
│              karakeep web                     │
│  ┌──────────────┐  ┌───────────────────┐      │
│  │  主内容区域    │  │  右侧聊天边栏      │      │
│  │  书签/预览/等  │  │  输入 → 搜索 → AI  │      │
│  └──────────────┘  └───────────────────┘      │
└──────────────────┬───────────────────────────┘
                   │
    ┌──────────────┼──────────────┐
    ▼              ▼              ▼
Meilisearch    AI 推理       Chat API (新增)
(全文搜索)    (deepseek)    /api/chat
                   │
              MCP Server (已有)
              + 权限层 (新增)
```

## 一、内置聊天侧边栏

### 1.1 API 端点

**新增 `POST /api/v1/chat`**

请求：
```json
{
  "message": "我收藏过哪些 MCP 项目？",
  "conversationId": "xxx" | null
}
```

处理流程：
1. 搜索 Meilisearch — 用用户问题作为查询，取 Top 10 书签
2. 构建 prompt — 搜索结果 + 书签摘要/标签/文件夹 → 发给 AI
3. AI 根据搜索结果回答，回答必须引用具体书签
4. 返回流式响应（SSE）或完整响应

响应：
```json
{
  "answer": "你收藏过这些 MCP 项目：\n1. 📖 [xxx](url) — 一个 MCP 服务器...\n2. ...",
  "sources": [
    { "id": "xxx", "title": "xxx", "url": "xxx" }
  ],
  "conversationId": "xxx"
}
```

### 1.2 AI Prompt 设计

```
System:
你是一个 AI 助手，帮助用户分析他们收藏的内容。
用户有这些文件夹：{folder list}

回答规则：
- 用中文回答
- 必须引用具体收藏来源，格式：📖 [标题](链接)
- 如果搜索结果不足，明确告诉用户
- 不要编造信息

User:
用户问题: {question}

相关收藏：
{搜索结果: 标题、摘要、标签、文件夹、URL}
```

### 1.3 对话历史

- 会话存于内存或轻量 DB 表（`chat_conversations`）
- 每次请求携带最近 N 条历史，供 AI 理解上下文
- 历史可在 UI 中清空

### 1.4 UI 组件

**右侧边栏** — 在现有布局中新增抽屉式侧边栏：
- 切换按钮（右上角 💬 图标）
- 对话列表（顶部）+ 输入框（底部）
- 消息气泡（用户 / AI）
- 回答中的引用链接可点击跳转到预览页
- 加载状态指示

### 1.5 安全

- 只搜索当前登录用户的书签
- 速率限制：每分钟 20 次
- 对话不持久化到磁盘（可选）

## 二、MCP Server 权限层

### 2.1 现有 API Key 系统

karakeep 已有 `apiKeys` 表，支持资源级别权限：

| Scope 格式 | 说明 |
|-----------|------|
| `fullaccess` | 全部权限 |
| `bookmarks:read` | 只读书签 |
| `bookmarks:readwrite` | 读写书签 |
| `lists:read` | 只读列表 |
| `lists:readwrite` | 读写列表 |
| `tags:readwrite` | 读写标签 |

### 2.2 MCP 分级

通过已有 scope 系统实现三级 MCP 权限（不需要新增基础设施）：

| 等级 | 需要的 Scope | 可用的 MCP 工具 |
|------|-------------|----------------|
| 🟢 只读 | `bookmarks:read` + `lists:read` | `search-bookmarks`, `get-bookmark`, `get-bookmark-content`, `get-lists` |
| 🟡 标准 | ↑ + `lists:readwrite` + `tags:readwrite` | ↑ + `add-bookmark-to-list`, `remove-bookmark-from-list`, `attach-tag`, `detach-tag`, `update-bookmark` |
| 🔴 完整 | `fullaccess` | ↑ + `create-bookmark`, `create-list`, `delete-bookmark` |

### 2.3 MCP Server 变更

`apps/mcp/src/` 中：
1. MCP 启动时读取 API Key 的 scope
2. 根据 scope 动态注册工具
3. 不再无差别暴露所有工具

## 三、安全总结

| 攻击面 | 防护 |
|--------|------|
| 数据泄露 | 聊天/MCP 都只访问当前用户数据 |
| 越权操作 | MCP 通过 API Key scope 限制 |
| API 滥用 | 速率限制 + 可选的 token 配额 |
| AI 幻觉 | 要求 AI 引用具体书签来源 |
| 数据持久化 | 聊天会话默认不持久化 |

## 实现计划

### Phase 1: Chat API + 侧边栏 (内置聊天)

| 步骤 | 内容 |
|------|------|
| 1 | 新增 `POST /api/v1/chat` 端点 |
| 2 | 实现 chat prompt 构建 + AI 调用 |
| 3 | 新增聊天侧边栏 UI 组件 |
| 4 | 切换按钮 + 对话 UI |
| 5 | 速率限制 |

### Phase 2: MCP 权限

| 步骤 | 内容 |
|------|------|
| 6 | MCP 读取 API Key scope |
| 7 | 根据 scope 动态注册工具 |
| 8 | 更新 README 文档 |

### Phase 3: 对话历史 (可选)

| 步骤 | 内容 |
|------|------|
| 9 | 对话持久化 |
| 10 | 历史管理 UI |
