# Karakeep Constitution

## Core Principles

### I. 采集优先 (Collection-First)
采集是产品的核心入口，一切功能围绕采集展开。采集体验必须做到：
- **零摩擦**：任何来源（浏览器插件、手机、API、RSS、CLI）都能在 2 秒内完成一条采集
- **全渠道统一**：所有渠道的采集数据汇入同一个视图，用户无需关心来源差异
- **即时反馈**：采集后立即在列表中可见，后台异步处理（爬取、AI 分析）不阻塞用户

### II. AI 理解闭环 (AI Understanding Loop)
采集不是终点，AI 理解才是价值所在。数据流必须完整覆盖：
- 采集 → 爬取页面内容 → AI 标签/摘要 → 知识沉淀
- 每条书签必须可追溯来源（source 字段）、可查看处理状态
- AI 分析结果（摘要、标签、评分）必须与原始书签强关联，不是割裂的模块

### III. 前端结构清晰 (Clear Frontend Structure)
页面职责单一，导航直觉化：
- **采集页**：所有未归档书签的收件箱，按时间排序，支持筛选和搜索
- **AI 理解页**：展示 AI 分析结果、处理进度、洞察摘要
- **标签/列表/归档**：组织和检索维度，不是独立的信息孤岛
- 侧边栏导航项必须有明确的功能定义，不出现"Home"这类模糊命名

### IV. 单一数据源 (Single Source of Truth)
- 所有采集渠道统一调用 `createBookmark` mutation，不绕过
- 书签是核心实体，标签、列表、Feed 是关联维度
- 去重在入口层处理，不靠 UI 层规避

### V. 渐进增强 (Progressive Enhancement)
- 基础功能（手动添加、列表浏览）不依赖外部服务
- AI 功能（摘要、标签、深度分析）作为增强层，失败不影响核心流程
- 搜索（Meilisearch）、AI（OpenAI）等可选服务降级时优雅处理

## 技术约束

- **Monorepo 架构**：Turborepo + pnpm，workspace 间通过包引用通信
- **前端**：Next.js 16 (App Router) + Tailwind CSS + shadcn/ui
- **数据层**：Drizzle ORM + SQLite/PostgreSQL，tRPC 提供类型安全 API
- **后台任务**：Worker 队列处理爬取、AI 推理、Feed 刷新等异步任务
- **类型安全**：Zod schema 定义所有输入输出，`pnpm typecheck` 是部署底线

## 开发工作流

- 遵循 Spec Kit 工作流：Constitution → Specify → Plan → Tasks → Implement
- 每次变更必须通过 typecheck
- 严禁未经用户确认推送到生产环境
- 提交前清理临时文件和备份

## Governance

本宪法是 karakeep 项目的核心约束，所有功能开发和重构必须符合上述原则。
修改宪法需要明确记录变更原因和影响范围。

**Version**: 1.0.0 | **Ratified**: 2026-06-18 | **Last Amended**: 2026-06-18
