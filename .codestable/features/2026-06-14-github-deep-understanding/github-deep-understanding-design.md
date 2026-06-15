---
doc_type: feature-design
feature: 2026-06-14-github-deep-understanding
status: approved
summary: GitHub 项目深度理解——把任意渠道进来的 GitHub 链接，自动消化成多层理解（humanSummary + agentDossier + 双标签 + 价值评分），排重、分类、归档，最终作为 Coding Agent 的第二大脑
tags: [github, second-brain, ai-analysis, dedup, classification]
---

# GitHub 项目深度理解

## 0. 术语约定

| 术语 | 定义 |
|------|------|
| GitHub 项目 | 唯一识别为 `owner/repo` 的 GitHub 仓库 |
| humanSummary | 30-60 字中文通俗总结，非技术人员可读 |
| agentDossier | JSON 结构的技术档案，供 AI Agent 做技术选型 |
| humanTags | 宽泛中文标签（"搜索" "数据库" "AI 工具"），UI 展示用 |
| agentTags | 精确英文标签（"full-text-search" "rust-actix"），Agent 搜索用 |
| 发现渠道 | 项目从哪个来源进入系统（X 推文 / 直接收藏 / RSS / 文章提及） |
| 价值评分 | AI 对项目"值得关注程度"的量化评估，决定入库 vs 归档 |
| 排重 | 同一 `owner/repo` 只保留一条记录，多渠道发现只追加来源 |

---

## 1. 决策与约束

### 需求摘要

**做什么**：把用户通过任何渠道收藏的 GitHub 项目链接，自动消化成**多层结构化理解**——非技术人员能看懂的人话总结、AI Agent 能消费的技术档案、两套标签体系（给人看 + 给 Agent 搜）、价值评估决定入库还是归档。同一项目从多个渠道进来不重复创建，只聚合发现来源。

**为谁**：
- **你（技术产品经理）**：刷 X/读文章时收藏项目 → 系统自动吃透 → 以后快速检索 + 分享给非技术同事
- **非技术协作者**：看到项目卡片上的人话总结就能懂项目是做什么的
- **Coding Agent**：通过 API / CLI 拿到完整技术档案，做技术选型推荐

**成功标准**：
- 收藏任意 GitHub 链接 → 自动创建 `github_projects` 记录，包含 humanSummary + agentDossier + 双标签
- humanSummary：非技术人员读完能复述"这项目是干什么的"（30-60 字中文）
- agentDossier：包含技术栈、架构、适用场景、替代品，Agent 可据此做决策判断
- 同一项目从 N 个渠道进来 → 只有 1 条项目记录 + N 条发现来源
- 低价值项目自动归档（不在主列表展示，但不删除）
- `karakeep agent find/recommend` 返回完整的 human + agent 双层数据

**明确不做**：
- 不做博主画像 / 博主追踪 / 博主信誉系统（只记录"谁分享的"作为来源上下文）
- 不爬取 GitHub 私有仓库
- 不做 GitHub OAuth 授权（只用公开 API）
- 不做 Agent 市场/插件系统
- 不主动扫描 X 时间线（被动等待用户收藏）
- 不删除任何数据（归档 = 标记，不是物理删除）
- 不修改现有书签系统的核心 CRUD 流程

### 关键决策

| 决策 | 选择 | 原因 |
|------|------|------|
| 项目唯一标识 | `fullName`（owner/repo） | GitHub 全局唯一，排重可靠 |
| humanSummary + agentDossier 生成 | AI 单次调用一次输出 | 减少 API 开销，保证两层语义对齐 |
| humanTags + agentTags | 同一 AI 调用输出两套 | humanTags 宽泛中文，agentTags 精确英文，各司其职 |
| 价值评分 | AI 输出 `valueScore: high/mid/low` + 规则兜底 | 灵活可调，低分自动归档 |
| 发现来源存储 | `projectRecommendations` 表 | 已存在，一对多支持多来源聚合 |
| 归档实现 | `githubProjects.archived` 布尔字段 | 轻量标记，不涉及数据搬迁 |
| 排重策略 | `fullName` 唯一约束（DB 层）+ 业务层先查后写 | 双重保障 |

### 复杂度档位

走默认档位。本 feature 不涉及高并发 / 对外 SDK / 跨节点事务。

---

## 2. 名词与编排

### 2.1 名词层

#### 现状

**github_projects 表**（已有，`packages/db/schema.ts`）：

```typescript
githubProjects = sqliteTable("githubProjects", {
  id, userId, bookmarkId,     // 基础关联
  fullName, url, name, owner, // GitHub 标识（fullName 唯一约束）
  description, stars, language, topics, homepage, license, // GitHub 元数据
  agentDossier,               // JSON，Agent 技术档案
  humanSummary,               // 人话总结
  aiStatus,                   // "none" | "pending" | "completed" | "failed"
  tags,                       // JSON string[]，给人看的标签
  pushedAt, lastFetchedAt,    // 时间戳
  createdAt, modifiedAt,
});
```

**project_recommendations 表**（已有）：

```typescript
projectRecommendations = sqliteTable("projectRecommendations", {
  id, projectId, bookmarkId,
  recommenderUsername, recommenderDisplayName, recommenderAvatarUrl,
  originalPostUrl, recommendationContext, recommendedAt,
  createdAt,
});
```

**现有 AI 分析流程**（`apps/workers/workers/inference/classify.ts`）：

- `classifyGitHubProject()` → 一次 AI 调用输出：summary + tags + targetFolder + agentDossier
- summary 是"投资人视角"的一句话（65 字内中文）
- agentDossier 含 purpose / techStack / architecture / keyFeatures / useCases
- 分析完成后更新 `githubProjects` 行，同时更新 bookmark summary + 标签 + 文件夹

**现有 GitHub Deep Dive**（`apps/workers/workers/githubDeepDiveWorker.ts`）：

- 单独的 worker，从 README 分析生成 humanSummary + agentDossier
- 由 `refreshBookmark` 或 `triggerDeepDive` tRPC 触发入队
- **当前两个分析流程并行存在，存在重复和冲突风险**

**现有自动创建逻辑**（`apps/workers/workers/inference/github.ts`）：

- `autoCreateGitHubBookmarks()` → 在 classify 完成后调用
- 检测 bookmark 内容中的 GitHub URL → 创建独立 bookmark + github_projects 记录
- 如果项目已存在（fullName 匹配），跳过不重复创建

#### 变化

**1. 数据模型变更**

`githubProjects` 表新增字段：

```typescript
// 新增字段
agentTags: text("agentTags", { mode: "json" }).$type<string[]>(), // 英文精确标签，Agent 搜索用
valueScore: text("valueScore", { enum: ["high", "mid", "low", "unscored"] })
  .notNull().default("unscored"),  // 价值评分
archived: integer("archived", { mode: "boolean" }).notNull().default(false), // 归档标记
archiveReason: text("archiveReason"), // 归档原因（低价值 / 不活跃 / 重复低质）
```

说明：
- `humanTags` = 现有 `tags` 字段，保持不变
- `agentTags` = 新增，与 `humanTags` 并行，同一 AI 调用一起生成
- `valueScore` + `archived` + `archiveReason` 构成归档机制

**2. 发现来源提取**（新流程，非新表）

当 bookmark 的 source URL 来自 X/Twitter 时，在爬虫完成后提取：
- 推文作者 (@handle)
- 推文原文（推荐语境）
- 推文发布时间
- 写入 `projectRecommendations`

**接口示例**：

```
输入：用户收藏 https://x.com/nicklama/status/123456  （内含 github.com/meilisearch/meilisearch）
输出：
  → github_projects: 创建 meilisearch/meilisearch（排重）
  → project_recommendations:
      recommenderUsername: "nicklama"
      recommendationContext: "MeiliSearch 太强了，部署只要 5 分钟"
      originalPostUrl: "https://x.com/nicklama/status/123456"
      recommendedAt: <推文时间>
  → AI 分析时融合推荐上下文到 humanSummary
```

**3. 双标签体系**

| 维度 | humanTags | agentTags |
|------|-----------|-----------|
| 语言 | 中文 | 英文 |
| 颗粒度 | 宽泛（"搜索" "数据库" "AI"） | 精确（"full-text-search" "vector-database" "llm-agent"） |
| 用途 | UI 展示、筛选 | Agent 搜索匹配 |
| 数量 | 2-4 个 | 5-10 个 |
| 存储 | `githubProjects.tags` | `githubProjects.agentTags`（新增） |

---

### 2.2 编排层

#### 现状

```
用户收藏 URL
  → crawlerWorker（爬取页面内容）
    → inferenceWorker classify（AI 分析）
      → classifyGitHubProject() 生成 summary + tags + agentDossier
      → autoCreateGitHubBookmarks() 检测内容中 GitHub URL
        → 创建 github_projects
  → [可选] githubDeepDiveWorker（README 深度分析）
    → 再次生成 humanSummary + agentDossier（与 classify 重复）
```

问题：
1. classifyGitHubProject 和 GitHubDeepDive 两套 AI 分析**并行冲突**
2. 没有提取 X/Twitter 推荐来源
3. 没有价值评分和归档
4. 没有 agentTags

#### 变化：统一的分析管线

```mermaid
flowchart TB
    subgraph 采集
        A[用户收藏 URL] --> B[crawlerWorker]
        B --> C{是否为 GitHub 直接链接?}
        C -->|是| D[提取 repo owner/name]
        C -->|否| E[爬取页面内容]
        E --> F[检测内容中 GitHub URL]
        F --> D
    end

    subgraph 排重
        D --> G{fullName 已存在?}
        G -->|否| H[fetchGitHubRepoMetadata<br/>创建 github_projects]
        G -->|是| I[跳过创建<br/>仅追加发现来源]
        H --> J[入队 GitHubDeepDive]
        I --> J
    end

    subgraph 来源提取
        B --> K{来源是 X/Twitter?}
        K -->|是| L[提取推文作者 + 原文]
        L --> M[写入 project_recommendations]
        K -->|否| N[跳过]
    end

    subgraph AI 深度理解（统一）
        J --> O[GitHubDeepDiveWorker]
        O --> P[fetchGitHubReadme]
        P --> Q[AI 一次调用:<br/>humanSummary + agentDossier<br/>+ humanTags + agentTags<br/>+ valueScore]
        Q --> R[写入 github_projects]
        M --> S[多来源聚合<br/>→ agentDossier 补充视角]
        S --> R
    end

    subgraph 归档决策
        R --> T{valueScore?}
        T -->|high/mid| U[入库，主列表展示]
        T -->|low| V[自动归档 archived=true]
        T -->|unscored| W[标记待确认]
    end

    subgraph 消费
        U --> X[Web UI 项目卡片]
        U --> Y[Agent CLI find/recommend]
        U --> Z[karakeep agent profile]
        V --> AA[归档列表<br/>不展示在主信息流]
    end
```

**流程级约束**：

| 约束 | 说明 |
|------|------|
| 排重优先级 | `fullName` 唯一约束 → 业务层先查后写 → 双重保障 |
| AI 超时 | 单次调用 60s，失败重试 1 次 |
| README 截断 | 超过 8000 字符截断（已有逻辑） |
| 价值评分兜底 | AI 输出 `unscored` 或评分缺失时，规则兜底：stars < 100 + 不活跃 → `low` |
| 归档后恢复 | 用户可手动取消归档，项目回到主列表 |
| 来源聚合 | 同一项目多条推荐 → agentDossier 不自动重写（避免覆盖），仅 `project_recommendations` 追加 |

---

### 2.3 挂载点清单

删了它 feature 是否消失？是才列：

| # | 挂载点 | 说明 |
|---|--------|------|
| 1 | `githubProjects` 表新增字段（agentTags / valueScore / archived / archiveReason） | 无这些字段则双标签 + 归档机制不存在 |
| 2 | `GitHubDeepDiveWorker` 统一 AI 分析（合并 classifyGitHubProject） | 无此 worker 则无人做深度分析 |
| 3 | X/Twitter 来源提取逻辑（爬虫完成后 → project_recommendations 写入） | 无此逻辑则发现来源丢失 |
| 4 | 价值评分 → 归档决策逻辑（AI 输出 + 规则兜底） | 无此逻辑则无自动归档 |
| 5 | `karakeep agent` CLI 返回 agentTags + valueScore | CLI 是 Agent 消费的主要入口 |

---

### 2.4 推进策略

```
1. 数据层：githubProjects 表新增字段 + 迁移
   退出信号：表字段生效，可读写 agentTags / valueScore / archived

2. AI 分析统一：GitHubDeepDiveWorker 升级 prompt → 一次输出 humanSummary + agentDossier + humanTags + agentTags + valueScore
   退出信号：收藏 GitHub 项目后自动生成完整五件套

3. 来源提取：爬虫完成后检测 X/Twitter 来源 → 提取推文信息 → 写入 project_recommendations
   退出信号：收藏 X 推文后 project_recommendations 表有正确记录

4. 归档决策：根据 valueScore + 规则兜底 → 自动标记 archived
   退出信号：低价值项目自动归档，高价值项目正常展示

5. CLI 扩展：karakeep agent find/project 返回 agentTags + valueScore + archived 状态
   退出信号：CLI --json 输出包含新字段

6. Web UI 调整：项目卡片显示归档状态 + 价值评分标记（可选：悬停显示 agentDossier）
   退出信号：归档项目有视觉标记，非归档项目正常展示
```

### 2.5 结构健康度与微重构

##### 评估

**文件级**：
- `apps/workers/workers/inference/classify.ts`（600+ 行）：职责包括通用 classify + GitHub 项目 classify + 文件夹分配 + GitHub 书签自动创建。**偏胖**。
- `apps/workers/workers/githubDeepDiveWorker.ts`（~200 行）：职责单一（README → AI 分析），行数合理。
- `apps/workers/workers/inference/github.ts`（~200 行）：职责单一（GitHub URL 检测 + 自动创建），行数合理。

**目录级**：
- `apps/workers/workers/inference/`：现有 5 文件（inferenceWorker.ts / summarize.ts / tagging.ts / classify.ts / github.ts），密度中等。

**结论**：做微重构（拆文件）。

`classify.ts` 中的 `classifyGitHubProject()` 和 `autoCreateGitHubBookmarks()`（实际在 `./github.ts` 但被 classify 调用）职责边界清晰但放在 classify.ts 里让该文件膨胀。将 classify.ts 中的 GitHub 相关逻辑拆出：

1. 把 `classifyGitHubProject()` 函数从 `classify.ts` 移到 `./github.ts`
2. `classify.ts` 中保留调用入口（按 `bookmarkData.githubProject` 判断路由到 `classifyGitHubProject`）
3. `GitHubDeepDiveWorker` 的 prompt 逻辑升级（不改文件结构，改 prompt 内容）

**搬迁方案**：
- `classify.ts` 中删除 `classifyGitHubProject()` 和 `gitHubResponseSchema` 定义
- `github.ts` 中新增导出的 `classifyGitHubProject()` 函数
- `classify.ts` 中 `import { classifyGitHubProject } from "./github"`
- 此为纯搬移，编译器全程绿灯

**实施时机**：本 feature 第 1 步之前，作为前置微重构。

**超出范围的观察**：无。

---

## 3. 验收契约

### 关键场景清单

| # | 触发 | 期望结果 |
|---|------|---------|
| 1 | 直接收藏 `https://github.com/meilisearch/meilisearch` | 创建 github_projects，humanSummary 非技术可读，agentDossier 含技术栈/架构/场景 |
| 2 | 收藏一篇含 GitHub 链接的文章（非直接项目 URL） | 自动检测内容中 GitHub URL，创建项目记录 + 独立书签，归入 "GitHub" 文件夹 |
| 3 | 同一个项目从两个不同渠道收藏 | 不重复创建，第二条仅追加 project_recommendations 来源记录 |
| 4 | 收藏 X 推文（含 GitHub 项目链接） | 推文作者 @handle + 原文被提取到 project_recommendations |
| 5 | 查看项目详情 | 展示 humanSummary + humanTags + stars/language；可选悬停展示 agentDossier + agentTags |
| 6 | 运行 `karakeep agent find "搜索" --json` | 返回 JSON，含 agentTags / valueScore / archived 字段 |
| 7 | 运行 `karakeep agent project owner/repo --json` | 返回完整项目数据，含 agentDossier / recommendations |
| 8 | 收藏低价值项目（stars < 100 + 不活跃 + AI 评 low） | 自动归档，不在主项目列表显示 |
| 9 | 手动取消归档 | 项目回到主列表，正常展示 |
| 10 | AI 分析超时或失败 | aiStatus = "failed"，不阻塞用户，可手动触发重试 |

### 明确不做反向核对

- 不记录博主身份之外的任何博主画像数据
- 不调用 GitHub API 写入任何数据
- 不爬取私有仓库
- 项目归档不是物理删除，不涉及 `DELETE` 操作
- 不主动扫描 X/Twitter 时间线或 RSS 源
- 不修改 `bookmarks` 核心表的 schema（只读已有 githubProject 关联）

---

## 4. 与项目级架构文档的关系

- `githubProjects` 表新增字段需写入 `docs/internal/architecture/02-data-model.md`
- 统一后的 AI 分析数据流需写入 `docs/internal/architecture/03-data-flow.md`
- ARCHITECTURE.md 中"已知约束"补充归档策略说明