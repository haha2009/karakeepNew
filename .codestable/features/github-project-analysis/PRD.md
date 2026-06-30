# PRD：GitHub 项目自动分析 + 多 AI 供应商管理

> 版本：v1.0 | 日期：2026-06-30 | 状态：待评审

---

## 1. 总览

### 1.1 背景

用户通过 X/Twitter 收藏了大量博主分享的 GitHub 项目链接。当前系统只能以普通书签形式存储，无法识别项目身份、无法自动提取项目信息。

### 1.2 目标

- **自动识别**收藏中的 GitHub 链接
- **自动分析**生成双层输出（人类可读 + Agent 可读）
- **自动归类**到"GitHub 项目"收藏夹
- **多供应商管理**：Admin 设置页可增删改查 + 切换 AI 供应商

### 1.3 范围

| 模块 | 说明 |
|------|------|
| 多 AI 供应商管理 | Admin 设置页 CRUD + 切换 |
| GitHub 项目检测 | crawlerWorker URL 识别 |
| AI 项目分析 | inferenceWorker 新增推理类型 |
| 双层输出 | Human summary + Agent dossier |
| GitHub 项目页 | 前端展示卡片列表 |

---

## 2. 用户故事

| # | 作为 | 我想 | 以便 |
|---|------|------|------|
| US-01 | 管理员 | 在设置页添加多个 AI 供应商（DeepSeek/OpenAI/Ollama） | 灵活切换不同的 AI 服务 |
| US-02 | 管理员 | 编辑/删除已有供应商 | 清理不再使用的 key |
| US-03 | 管理员 | 切换当前活跃供应商 | 用不同模型跑不同任务 |
| US-04 | 用户 | 收藏一个 GitHub 链接 | 系统自动识别为项目 |
| US-05 | 用户 | 看到项目的"人话"描述 | 快速知道这个项目是干嘛的 |
| US-06 | 用户 | 在 GitHub 项目页浏览所有收藏的项目 | 像看 Stars 列表一样看收藏 |
| US-07 | AI Agent | 查询结构化项目数据 | 做第二大脑推荐 |
| US-08 | 管理员 | 批量重新分析已有的 GitHub 书签 | 补跑历史数据 |

---

## 3. 多 AI 供应商管理

### 3.1 当前状态

```
providerConfig 表（单行）
├── id: "default"（硬编码主键 = 只有一行）
├── baseUrl, apiKey, textModel, imageModel, outputSchema
└── Admin 页面：编辑当前行，无列表/切换/删除
```

### 3.2 目标状态

```
ai_providers 表
├── id: UUID
├── name: "DeepSeek"                    ← 供应商名称
├── apiKey: "sk-xxx"                    ← 加密存储
├── baseUrl: "https://api.deepseek.com" ← API 地址
├── textModel: "deepseek-chat"          ← 文本模型
├── imageModel: "deepseek-chat"         ← 图片模型（可选）
├── proxyUrl: "http://..."              ← 代理（可选）
├── outputSchema: "json"                ← 输出格式
├── isDefault: true/false               ← 默认供应商
├── isActive: true/false                ← 启用/禁用
├── createdAt, updatedAt
└── 排序：isDefault 降序 → createdAt 降序
```

### 3.3 功能需求

| 操作 | 说明 |
|------|------|
| **新增** | 填写 name/apiKey/baseUrl/textModel，可填 imageModel/proxyUrl |
| **列表** | 显示所有供应商，标注哪个是默认、哪个是当前活跃 |
| **编辑** | 修改任意字段，保存 |
| **删除** | 删除供应商，至少保留一个活跃供应商（阻止删除最后一个） |
| **设为默认** | 点击卡片上的"设默认"按钮，切换 isDefault |
| **设为活跃** | 推理时用 isActive=true 且 isDefault 的供应商 |
| **测试连接** | 发送一条测试消息确认 key 有效 |
| **Key 脱敏** | 显示时只显示前 8 位 + ... + 后 4 位 |

### 3.4 前端交互

```
┌──────────────────────────────────────────────────────┐
│ AI 供应商管理                                         │
│                                                       │
│ ┌─────────────────────────────────────────────────┐ │
│ │ [✦ 默认]  DeepSeek                    [编辑][删除] │ │
│ │  API: sk-9a3f...2b1c                            │ │
│ │  Model: deepseek-chat                            │ │
│ └─────────────────────────────────────────────────┘ │
│                                                       │
│ ┌─────────────────────────────────────────────────┐ │
│ │          OpenAI                 [设为默认][编辑][删除] │ │
│ │  API: sk-d4e8...9f2a                            │ │
│ │  Model: gpt-4.1-mini                            │ │
│ └─────────────────────────────────────────────────┘ │
│                                                       │
│            [+ 添加供应商]                              │
└──────────────────────────────────────────────────────┘
```

新增/编辑表单字段：

| 字段 | 必填 | 默认值 | 说明 |
|------|:----:|--------|------|
| 名称 | ✅ | — | 自定义名称，如"DeepSeek" |
| API Key | ✅ | — | 密码输入框 |
| Base URL | ✅ | https://api.openai.com/v1 | OpenAI 兼容地址 |
| 文本模型 | ✅ | deepseek-chat | 如 deepseek-chat / gpt-4.1-mini |
| 图片模型 | ❌ | 同文本模型 | 多模态模型 |
| 代理地址 | ❌ | 空 | 如 http://127.0.0.1:1080 |
| 设为默认 | ❌ | 否 | checkbox，同组只能有一个 checked |

### 3.5 后端变更

#### Schema 变更

```sql
-- 新增表
CREATE TABLE ai_providers (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)))),
  name TEXT NOT NULL DEFAULT '默认供应商',
  apiKey TEXT,
  baseUrl TEXT,
  textModel TEXT NOT NULL DEFAULT 'deepseek-chat',
  imageModel TEXT,
  proxyUrl TEXT,
  outputSchema TEXT DEFAULT 'json',
  isDefault INTEGER DEFAULT 0,
  isActive INTEGER DEFAULT 1,
  createdAt INTEGER DEFAULT (unixepoch()),
  updatedAt INTEGER DEFAULT (unixepoch())
);

-- 迁移旧数据（如果存在）
INSERT INTO ai_providers SELECT * FROM providerConfig WHERE TRUE;

-- 保留 providerConfig 表但不使用（过渡期）
```

#### tRPC Router 变更

| 方法 | 变更 |
|------|------|
| `admin.getProviderConfig` | 废弃 → 改为返回 `ai_providers` 列表 |
| `admin.saveProviderConfig` | 废弃 → 拆分为 CRUD |
| 新增 `admin.aiProviders.list` | 获取所有供应商 |
| 新增 `admin.aiProviders.create` | 添加供应商 |
| 新增 `admin.aiProviders.update` | 编辑（全字段覆盖） |
| 新增 `admin.aiProviders.remove` | 删除（校验至少保留一个） |
| 新增 `admin.aiProviders.setDefault` | 设为默认 |
| 新增 `admin.aiProviders.test` | 测试连接 |

#### 运行时读取逻辑

```
InferenceClient 工厂 ──────────────────────────────────┐
                                                        │
  buildInferenceClient()                                │
      │                                                 │
      ▼                                                 │
  SELECT * FROM ai_providers WHERE isActive=1           │
  ORDER BY isDefault DESC, createdAt DESC               │
  LIMIT 1  ← 取第一个（默认优先）                        │
      │                                                 │
      ▼                                                 │
  baseURL / apiKey / textModel / imageModel / proxyUrl  │
      │                                                 │
      ▼                                                 │
  返回 OpenAIInferenceClient 或 OllamaInferenceClient   │
                                                        │
  inference worker 调用时无需改动（走现有 factory）      │
```

**关键约束**：推理时动态从 DB 读供应商配置，**不依赖环境变量**。env 变量只作为 fallback（首次部署还没进 Admin 页时）。

---

## 4. GitHub 项目自动分析

### 4.1 数据流

```
用户收藏 https://github.com/meilisearch/meilisearch
    │
    ▼
crawlerWorker 完成爬取
    │ 新增：URL 匹配 /github\.com\/([^\/]+)\/([^\/]+)/
    │   owner = "meilisearch", repo = "meilisearch"
    │
    ▼
enqueue inference job, type = "project-analysis"
    │
    ▼
inferenceWorker 收到 type = "project-analysis"
    │
    ├── 从 bookmark 获取: url, title, description, content
    ├── 调用 GitHub API（可选，取 stars/language/topics）
    │   注意：走 proxyUrl（国内可能需要代理）
    │
    ├── 一次 AI 调用，要求返回 JSON：
    │   {
    │     humanSummary: "一个快速的全文搜索引擎，个人部署超简单",
    │     agentDossier: {
    │       category: "搜索 / 数据库",
    │       techStack: ["Rust", "Actix-web"],
    │       useCases: ["全文搜索", "日志分析", "电商搜索"],
    │       bestFor: ["想自己搭搜索引擎的个人开发者"],
    │       alternatives: ["Elasticsearch", "Tantivy", "MeiliSearch"],
    │       pros: ["部署简单", "性能好", "中文支持好"],
    │       cons: ["写并发不如 ES", "生态不如 ES 成熟"]
    │     },
    │     tags: ["search", "rust", "self-hosted"]
    │   }
    │
    ▼
写入 bookmark:
    ├── summary = humanSummary
    ├── ai_tags = tags (合并现有，不重复)
    ├── projectInsights = agentDossier (JSON 字段，新增)
    ├── projectAnalysisStatus = "success"
    │
    ▼
自动归入 "GitHub 项目" 收藏夹
    │ 如果不存在则自动创建
    │
    ▼
触发搜索索引更新
```

### 4.2 AI Prompt

```
# 任务
分析一个 GitHub 开源项目，返回结构化 JSON。

## 项目信息
URL: {url}
标题: {title}
描述: {description}
正文: {content (截断到 3000 字)}

## 输出要求（严格 JSON，不要其他内容）
{
  "humanSummary": "≤30 字的白话文，说清这个项目是干嘛的，面向非技术人员",
  "agentDossier": {
    "category": "分类，如：搜索 / 数据库 / AI 工具 / 前端框架",
    "techStack": ["主要技术栈"],
    "useCases": ["适用场景 3-5 个"],
    "bestFor": ["最适合谁用"],
    "alternatives": ["同类替代方案"],
    "pros": ["优点 2-3 个"],
    "cons": ["缺点 1-2 个"]
  },
  "tags": ["3-5 个英文小写标签，用连字符"]
}
```

### 4.3 数据库变更

```typescript
// bookmarks 表新增字段
classificationStatus: text("classificationStatus", {
  enum: ["pending", "failure", "success"]
}).default("pending"),

projectInsights: text("projectInsights").optional(),  // JSON
projectAnalysisStatus: text("projectAnalysisStatus").optional(), // pending/success/failure
```

### 4.4 目录变更

```
apps/workers/workers/inference/
├── inferenceWorker.ts    ← 新增 case "project-analysis"
├── summarize.ts
├── tagging.ts
├── classify.ts
└── projectAnalysis.ts    ← 新增
```

### 4.5 错误处理

| 错误 | 处理 |
|------|------|
| GitHub API 限流 | 跳过 API 数据，只做 AI 分析（基于页面内容） |
| AI 调用超时 | 重试 1 次，仍失败打 status=failure |
| AI 返回非法 JSON | fallback 到空 agentDossier，只存 humanSummary |
| 非 GitHub 链接 | 走正常 tag/summarize 流程，不影响 |

---

## 5. GitHub 项目展示页

### 5.1 路径

```
/dashboard/github-projects       ← 列表页
```

### 5.2 卡片设计（人看的）

```
┌──────────────────────────────────────────┐
│  MeiliSearch              ⭐ 22.3k  Rust │
│ ──────────────────────────────────────── │
│  一个快速的全文字搜索工具，个人部署特别简单  │
│                                          │
│  #search  #rust  #self-hosted           │
│                                          │
│  适用：博客搜索、文档站、电商搜索            │
└──────────────────────────────────────────┘
```

- **不显示** techStack details, pros/cons, alternatives（人看不懂）
- **显示** stars（从 GitHub API 或页面内容提取）、一句话描述、通俗标签
- **统计**：顶部显示共多少个项目，按语言分布，按分类分布

### 5.3 Agent 数据接口

```
GET /api/trpc/githubProjects.list
← 返回全部项目的 agentDossier 字段
← Agent 通过 trpc 直接查询
```

---

## 6. 与现有系统的集成

### 6.1 复用现有组件

| 现有模块 | 复用方式 |
|---------|---------|
| `providerConfig` → `inference.ts` | 工厂方法改从 DB 读 `ai_providers` |
| `inferenceWorker.ts` | 新增 `case "project-analysis"` |
| `RuleEngine.triggerOnEvent` | 分析完成后触发（同 tag/summarize 流程） |
| `connectTags` | 复用标签关联逻辑 |
| `triggerSearchReindex` | 分析完成后更新搜索索引 |

### 6.2 不改动的模块

| 模块 | 原因 |
|------|------|
| `crawlerWorker.ts` 主体 | 只新增 URL 检测逻辑，不重构 |
| `tagging.ts` | 独立功能，不合并 |
| `summarize.ts` | 独立功能，不合并 |
| `classify.ts` | 独立功能，不合并（可后续融合）|
| `schema.ts` 其他表 | 只新增字段，不改动现有 |

---

## 7. 开发计划

### Phase 1：多 AI 供应商管理（2 天）

- [ ] DB: 新建 `ai_providers` 表 + 迁移脚本
- [ ] tRPC: 6 个新方法（CRUD + setDefault + test）
- [ ] UI: 供应商管理页（列表 + 新增/编辑弹窗）
- [ ] Inference: 工厂方法改读 DB
- [ ] 迁移旧 `providerConfig` 数据

### Phase 2：GitHub 项目自动分析（2 天）

- [ ] crawlerWorker: URL 检测 + enqueue project-analysis
- [ ] inference: 新增 `projectAnalysis.ts`
- [ ] DB: bookmarks 表新增字段 + 迁移
- [ ] prompt 设计 + 验证
- [ ] 自动归入"GitHub 项目"文件夹

### Phase 3：展示页（1-2 天）

- [ ] GitHub 项目列表页 `/dashboard/github-projects`
- [ ] 卡片组件（人看的简化版）
- [ ] 筛选/搜索（按语言/分类/标签）
- [ ] trpc route 暴露 agentDossier

### Phase 4：批量处理（半天）

- [ ] Admin 页"重新分析"按钮
- [ ] 批量 job 机制（后台跑，不阻塞）

---

## 8. 验收标准

| 场景 | 预期 |
|------|------|
| 添加供应商 | 列表出现，可设为默认，推理使用该供应商 |
| 切换供应商 | 推理结果立即使用新供应商的模型 |
| 删除供应商 | 删除后列表更新，最后一个不能删 |
| 收藏 GitHub 链接 | 自动显示人话描述 + 标签 + 归入文件夹 |
| 访问 GitHub 项目页 | 显示所有收藏的 GitHub 项目卡片 |
| Agent 查询 | 返回结构化 projectInsights |
| 批量重新分析 | 后台 job 跑完，所有卡片更新 |

---

## 9. 不做的事

| 不做 | 原因 |
|------|------|
| 不嵌入完整知识库系统（RAG/FastGPT） | 过度工程，当前需求不需要 |
| 不做向量搜索 | 用 Meilisearch 全文搜索够用 |
| 不做知识图谱 | Phase 2-3 之后再考虑 |
| 不跑 Meilisearch 以外的搜索服务 | 资源有限 |
| 不改动 tagging/summarize/classify | 独立功能，Phase 1/2 完成后考虑融合 |
| 不做移动端适配 | 桌面端优先 |
| 不保留 `providerConfig` 表 | 迁移后删除 |
