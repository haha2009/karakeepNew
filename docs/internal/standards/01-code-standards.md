# 代码规范

## TypeScript

- **严格模式**: `strict: true`，禁止使用 `any` (用 `unknown` 替代)
- **命名风格**:
  - 文件/目录: kebab-case (bookmark-list.tsx)
  - 组件: PascalCase (BookmarkList)
  - 函数/变量: camelCase (fetchBookmarks)
  - 常量: UPPER_SNAKE (MAX_RETRY_COUNT)
  - 类型/接口: PascalCase (BookmarkData)
  - 枚举: PascalCase (BookmarkStatus)
- **导入顺序**: 外部库 → 内部包 → 相对路径
- **类型优先**: 优先定义 type，interface 仅用于 class 实现

## React / Next.js

- **App Router**: 使用 app 目录结构，不使用 pages router
- **Server Component First**: 默认使用 Server Component，需要交互时加 `"use client"`
- **状态管理**: React state + URL search params 优先，避免全局状态
- **tRPC**: 所有 API 调用通过 tRPC，不直接 fetch
- **shadcn/ui**: UI 组件使用 shadcn，不重复造轮子
- **Tailwind**: 使用 Tailwind 样式，避免 CSS 模块或 styled-components

## 数据库 (Drizzle)

- **Schema 定义**: `packages/db/schema.ts` 集中管理
- **迁移**: 每次 schema 变更生成独立 migration 文件
- **关系**: 使用 Drizzle relations API 定义关系
- **类型**: 导出的类型通过 `typeof` schema 表推断

## tRPC 路由

- **按资源分文件**: bookmarks.ts、tags.ts、lists.ts 等
- **Router 文件导出** `appRouter` 类型用于客户端
- **Procedure 命名**: 动词 + 资源 (createBookmark, listBookmarks)
- **输入验证**: 使用 zod schema 验证所有输入

## 代码样式

- **格式化**: oxfmt (Prettier 替代)
- **Lint**: oxlint (ESLint 替代)
- **最大行宽**: 100 字符
- **分号**: 必须
- **引号**: 单引号优先
- **尾逗号**: 全部

## 禁止行为

- ❌ 使用 `any` 类型
- ❌ 直接 `fetch` 跳过后端 API
- ❌ console.log 提交到代码
- ❌ 硬编码敏感信息
- ❌ 不必要的 `"use client"` 指令
