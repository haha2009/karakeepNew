---
doc_type: feature-design
feature: 2026-06-06-bookmark-agent
status: approved
summary: 书签 Agent — GitHub 项目追踪 + 博主推荐映射 + 双层级总结（Human 易懂/Agent 深度）+ Agent CLI 外部大脑
tags: [agent, github, projects, recommendations, cli, second-brain]
---

# Bookmark Agent — 开发者第二大脑

## 0. 术语约定

| 术语 | 定义 |
|------|------|
| GitHub Project | 收藏的 GitHub 仓库，核心实体 |
| Project Tag | 给人看的简单标签（"搜索" "数据库" "AI 工具"），自动生成 |
| Human Summary | 一句话非技术描述，让不懂技术的人看懂这项目干嘛的 |
| Agent Dossier | 给 AI Agent 看的深度项目档案，含技术栈/架构/优劣势/博主视角 |
| Recommendation | 博主推荐记录：谁推荐的、怎么说的、什么时候 |
| Interest Profile | 用户兴趣画像：从收藏项目中自动归纳的技术方向偏好 |
| Agent CLI | `karakeep agent` 命令，供其他 AI Agent 查询"第二大脑" |
| Multi-Perspective Summary | 同一个项目被多个博主推荐时，聚合各方视角的综合总结 |

## 1. 决策与约束

### 需求摘要

**做什么**：把 Karakeep 从"书签管理工具"升级为"开发者第二大脑"。自动识别 GitHub 项目收藏，提取元数据，生成双层级总结（人易懂 + Agent 深度），追踪博主推荐关系，提供 Agent CLI 让其他 AI Agent 查询。

**为谁**：
- 人（你）：不懂技术也能看懂的标签 + 一句话总结
- AI Agent：深度项目档案，vibe coding 时自动匹配最佳方案

**成功标准**：
- 收藏任何 GitHub 链接后自动提取项目元数据（stars/language/description）
- 自动生成 Human Summary：一句话说清项目是做什么的（非技术视角）
- 自动生成 Agent Dossier：完整技术档案，Agent 可据此做决策
- 同一个项目被多个博主推荐时自动聚合，多视角总结
- `karakeep agent` CLI 可供其他 Agent 查询项目库
- Vibe coding 时 Agent 能根据当前需求推荐你收藏过的最合适项目

**明确不做**：
- 不爬取 GitHub 私有仓库
- 不做 GitHub OAuth 授权（只用公开 API）
- 不做 Agent 市场/插件系统
- CLI 只做查询不做修改操作（查询外部大脑，不写数据）

### 关键决策

| 决策 | 选择 | 原因 |
|------|------|------|
| GitHub 数据来源 | GitHub REST API | 公开数据，无需 OAuth |
| 项目唯一标识 | `owner/repo` | 防重复，跨用户共享 |
| 双层级总结生成 | AI 一次调用输出 Human + Agent | 减少 API 调用次数 |
| Agent CLI 协议 | JSON stdout，pipe-friendly | 任何 Agent 都可以 `karakeep agent query "..." --json` |
| 博主识别 | 从 bookmark 元数据提取 | 浏览器扩展/手动输入 |
| 标签系统 | 自动生成 + 人工可改 | 保持灵活 |

### 前置依赖

- GitHub 公开 API 无需 key，但有 rate limit（60 req/h）；建议配置 `GITHUB_TOKEN` 提高配额

## 2. 名词与编排

### 2.1 名词层

#### 现状

- **bookmarks** 表：核心实体，存 url/title/description/summary/tags/content，不支持项目结构
- **tags** 表：简单标签名 + 颜色
- **lists** 表：文件夹，可嵌套
- **爬虫系统**：Playwright 爬取 URL 内容，提取 title/description
- **inference worker**：summarize（摘要）/ tag（打标签）/ classify（归类）三种 AI 推理

#### 变化：新增实体

##### github_projects 表

| 字段 | 类型 | 说明 |
|------|------|------|
| id | text (UUID) | 主键 |
| owner | text | GitHub owner |
| name | text | GitHub repo name |
| fullName | text | `owner/repo`，唯一约束 |
| description | text | GitHub 官方描述 |
| language | text | 主语言（Rust / TypeScript / Python） |
| topics | JSON | GitHub topics 标签 |
| stars | int | star 数 |
| url | text | `https://github.com/owner/repo` |
| lastCommitAt | datetime | 最后提交时间 |
| lastReleaseAt | datetime | 最后 release 时间 |
| humanSummary | text | 一句话非技术总结（给人看） |
| agentDossier | JSON | 深度项目档案（给 Agent 看，见下文） |
| tags | JSON | 自动生成的项目标签（"搜索" "AI" "数据库"） |
| fetchedAt | datetime | GitHub API 最后同步时间 |
| createdAt | datetime | |
| updatedAt | datetime | |

##### project_recommendations 表

| 字段 | 类型 | 说明 |
|------|------|------|
| id | text (UUID) | 主键 |
| projectId | text | FK → github_projects |
| bookmarkId | text | FK → bookmarks（原始收藏） |
| userId | text | FK → users |
| recommender | text | 推荐人（博主 X handle，如 `@nicklama`） |
| recommenderUrl | text | X/twitter 链接 |
| originalContext | text | 博主推荐时的原话 |
| recommendedAt | datetime | 推荐时间 |
| source | enum | `twitter` / `manual` / `rss` / `other` |

##### project_tags 表（可选，自动生成 + 人工维护）

| 字段 | 说明 |
|------|------|
| id | |
| name | 标签名（"搜索引擎" "数据库" "AI 工具" "前端框架"） |
| color | 显示颜色 |
| isAuto | 是否 AI 自动生成 |

##### agent_dossier 结构（JSON，存在 github_projects.agentDossier）

```json
{
  "summary": "项目一句话总结（技术视角）",
  "techStack": ["Rust", "Actix-web", "MeiliSearch"],
  "architecture": "描述项目架构",
  "useCases": ["全文搜索", "日志分析", "电商搜索"],
  "pros": ["部署简单", "性能好", "中文支持好"],
  "cons": ["不适合高并发写场景"],
  "alternatives": ["Elasticsearch", "Tantivy"],
  "bloggerPerspectives": [
    {
      "blogger": "@nicklama",
      "say": "适合个人项目，部署太简单了",
      "sentiment": "positive"
    }
  ],
  "recommendedFor": ["个人博客搜索", "小型文档站"],
  "tags": ["搜索", "Rust", "自托管"]
}
```

#### 接口示例

**检测 GitHub 项目并建立关联**（自动流程，无用户操作）：
```
输入：用户收藏 https://github.com/meilisearch/meilisearch
输出：→ 识别为 GitHub 项目
     → 提取 owner=meilisearch, name=meilisearch
     → GitHub API: fetch metadata
     → AI: 生成 humanSummary + agentDossier + tags
     → 写入 github_projects 表
     → 如果来自 X 推荐，写入 project_recommendations
// 来源：apps/workers/workers/inference/（新增 projectAnalyzer.ts）
```

**Agent CLI 查询**：
```bash
# 给人看
karakeep agent find "搜索"
> 🔍 MeiliSearch — 一个快速搜索工具，帮你从大量内容中找到想要的东西
>    标签: #搜索 #Rust #自托管  ❤️ 22.3k ⭐

# 给 Agent 看
karakeep agent find "搜索" --json
> [{
>   "fullName": "meilisearch/meilisearch",
>   "humanSummary": "一个快速搜索工具...",
>   "agentDossier": { "techStack": ["Rust"], "useCases": [...], ... },
>   "stars": 22300,
>   "tags": ["搜索", "Rust"]
> }]

# 查询项目详情（Agent）
karakeep agent project meilisearch/meilisearch --dossier
> { 完整 agentDossier，含所有博主视角 }

# 兴趣画像（Agent）
karakeep agent profile
> {
>   "topLanguages": ["Rust", "TypeScript", "Python"],
>   "topTopics": ["search", "database", "ai"],
>   "recentTrend": "从前端转向 AI 基础设施",
>   "recommendedExploration": ["消息队列", "嵌入式数据库"]
> }
// 来源：apps/cli/（karakeep agent 子命令，新增或扩展现有 CLI）
```

**Web UI 项目卡片**（给人看）：
```
┌─────────────────────────────────────┐
│  MeiliSearch          ⭐ 22.3k  Rust │
│  一个快速搜索工具，让你从大量       │
│  内容中找到想要的东西               │
│                                     │
│  #搜索  #自托管  #全文索引          │
│                                     │
│  📌 @nicklama 推荐 · 3天前          │
│  "部署太简单了，个人项目神器"       │
└─────────────────────────────────────┘
// 来源：apps/web/components/dashboard/agent/（新增组件）
```

### 2.2 编排层

```mermaid
flowchart TB
    subgraph 数据采集
        A[用户收藏 GitHub 链接] --> B{是 GitHub repo？}
        B -->|否| C[普通书签流程]
        B -->|是| D[GitHub API: 获取元数据]
        D --> E{来自 X/Twitter？}
        E -->|是| F[提取博主 + 推荐原文]
        E -->|否| G[跳过推荐记录]
    end

    subgraph AI 处理
        D --> H[AI 生成 Human Summary]
        D --> I[AI 生成 Agent Dossier]
        D --> J[AI 生成 Tags]
        H --> K[存入 github_projects]
        I --> K
        J --> K
        F --> L[存入 project_recommendations]
    end

    subgraph 双层级输出
        K --> M[Web UI: 项目卡片]
        K --> N[Agent CLI: human summary]
        K --> O[Agent CLI: dossier]
        L --> P[多视角聚合总结]
        P --> M
        P --> O
    end

    subgraph Vibe Coding 场景
        Q[用户: "我想做个搜索功能"] --> R[Agent 查第二大脑]
        R --> S["发现 MeiliSearch ✓ 适合你的场景"]
        R --> T["收藏过 Tantivy，但性能过剩"]
        R --> U["推荐: 用 MeiliSearch 快速搭建"]
    end
```

#### 现状

- 收藏流程：用户添加 URL → 爬取 → inference（摘要/标签/归类）→ 完成
- 没有项目识别、没有博主追踪、没有双层级输出

#### 变化

| 步骤 | 变化 |
|------|------|
| 收藏阶段 | 新增 GitHub URL 检测 → 异步 fetch GitHub API |
| inference 阶段 | 新增 `analyze-project` 推理类型：生成 humanSummary + agentDossier + tags |
| 推荐追踪 | 从 bookmark 来源提取博主信息 → 写入 project_recommendations |
| 多视角聚合 | 同项目多条推荐 → 聚合到 agentDossier.bloggerPerspectives |
| 输出层 | Web UI 项目卡片 + Agent CLI JSON 输出 |

#### 流程级约束

| 约束 | 说明 |
|------|------|
| GitHub API 限流 | 60 req/h（未认证），配置 GITHUB_TOKEN 后 5000 req/h |
| AI 超时 | 分析项目单次调用 30s，失败后重试 1 次 |
| 重复去重 | `fullName` 唯一约束，重复收藏只追加推荐记录 |
| 增量更新 | GitHub 数据 24h 内不重复 fetch，stars 变化触发的更新走队列 |

### 2.3 挂载点清单

| 挂载位置 | 具体文件 | 动作 |
|---------|---------|------|
| 数据库 Schema | `packages/db/schema/` — 新增 `github_projects` + `project_recommendations` | 新增迁移 |
| Inference Worker | `apps/workers/workers/inference/inferenceWorker.ts` — 新增 `analyze-project` 类型 | 修改 |
| CLI 扩展 | `apps/cli/` — 新增 `agent` 子命令 (`agent find/project/profile`) | 新增 |
| Web UI 路由 | `apps/web/` — 新增项目卡片组件 + Agent 面板 | 新增 |
| API 路由 | `packages/api/index.ts` — 新增 `/projects` 路由 | 新增 |

### 2.4 推进策略

```
1. 数据层：github_projects + project_recommendations 表 + 迁移
   退出信号：表创建成功，可读写

2. GitHub 检测：URL 中识别 github.com/owner/repo → fetch API 元数据
   退出信号：收藏 GitHub 链接后自动获取 stars/language/topics

3. AI 分析：新增 analyze-project 推理类型 → 生成 humanSummary + agentDossier + tags
   退出信号：收藏项目后自动生成双层级总结

4. 博主追踪：从 X 收藏提取推荐人 + 原文 → 写入 project_recommendations
   退出信号：同项目多个推荐被正确聚合，多视角总结生成

5. Web UI：项目卡片组件 + 标签展示 + 博主推荐列表
   退出信号：页面展示所有项目、标签、推荐关系

6. Agent CLI：karakeep agent find/project/profile → JSON 输出
   退出信号：`karakeep agent find "rust" --json` 返回正确 JSON

7. 兴趣画像：从所有收藏项目自动归纳兴趣方向
   退出信号：karakeep agent profile 展示准确的兴趣分析

8. Vibe Coding 场景验证：模拟 "我想做个 X" → Agent 推荐最匹配项目
   退出信号：推荐结果人工判断合理
```

### 2.5 结构健康度与微重构

##### 评估

- 文件级 — `apps/workers/workers/inference/inferenceWorker.ts`（143 行）：职责清晰，行数合理
- 文件级 — `apps/cli/`：已有 CLI 框架，新增 `agent` 子命令不会导致拥挤
- 目录级 — `apps/workers/workers/inference/`：现有 4 文件（inferenceWorker/summarize/tagging/classify），新增 `projectAnalyzer.ts` 合理

##### 结论：不做

文件健康和目录组织均合理，改动量小，无需微重构。

## 3. 验收契约

### 关键场景清单

| # | 触发 | 期望结果 |
|---|------|---------|
| 1 | 收藏 `https://github.com/meilisearch/meilisearch` | 自动识别为 GitHub 项目，显示 stars/language/topics |
| 2 | 收藏后查看项目卡片 | 显示 Human Summary（一句非技术描述）+ 标签 |
| 3 | 从 X 收藏某博主推荐的项目 | 记录 `@博主` + 推荐原文到推荐列表 |
| 4 | 同一个项目被 3 个博主推荐 | 项目页展示 3 个博主的不同观点 |
| 5 | 运行 `karakeep agent find "搜索"` | 返回匹配的项目列表（Human 格式） |
| 6 | 运行 `karakeep agent find "搜索" --json` | 返回 JSON，含 agentDossier |
| 7 | 运行 `karakeep agent profile` | 返回兴趣画像：top languages / topics / 趋势 |
| 8 | 对 Agent 说"我想做个全文搜索功能" | Agent 推荐 MeiliSearch，说明原因 |
| 9 | 收藏同一个项目两次 | 不会创建重复项目，只追加推荐记录 |
| 10 | 收藏非 GitHub 链接 | 走正常书签流程，不影响项目系统 |

### 明确不做反向核对

- 不调用 GitHub API 写入任何数据
- Agent CLI 不做修改操作（无 `karakeep agent delete/edit`）
- 不识别/处理 GitHub 私有仓库
- 收藏非 GitHub 链接不会创建 `github_projects` 记录

## 4. 与项目级架构文档的关系

- 新增 `github_projects` + `project_recommendations` 表需写入 `docs/internal/architecture/02-data-model.md`
- 新增项目分析流程需写入 `docs/internal/architecture/03-data-flow.md`
- Agent CLI 协议需写入 `apps/cli/README.md`
- ARCHITECTURE.md 子系统索引新增"项目分析系统"
