# 采集页面优化规格 (Spec)

## Context

karakeep 的"采集"页 (`/dashboard/bookmarks`) 是用户登录后的首页，展示所有未归档书签。当前存在三个核心问题：
1. **来源不可见** — 7 个采集渠道的数据看起来一模一样
2. **状态不可见** — AI 处理进度（爬取/标签/摘要）几乎无反馈
3. **管理入口深藏** — RSS 订阅管理在 /settings/feeds，与采集体验割裂

目标：让采集页成为真正的"采集总控台"——一眼看出内容从哪来、处理到什么程度、快速筛选和管理。

---

## Phase 1: P0 — 来源标识 + 处理状态（纯前端，无需后端改动）

### 1.1 来源标识 (SourceBadge)

**改什么：** 在每张书签卡片底部行显示来源小图标

**改动文件：**
- 新建 `apps/web/components/dashboard/bookmarks/SourceBadge.tsx`
- 修改 `apps/web/components/dashboard/bookmarks/BookmarkLayoutAdaptingCard.tsx` — BottomRow 集成 SourceBadge

**来源映射：**
| source | 图标 (lucide) | 标签 | 颜色 |
|--------|-------------|------|------|
| extension | Puzzle | 插件 | blue |
| rss | Rss | RSS | orange |
| mobile | Smartphone | 手机 | green |
| web | Globe | 网页 | purple |
| cli | Terminal | CLI | gray |
| api | Code | API | pink |
| import | FileUp | 导入 | yellow |
| singlefile | FileText | 归档 | teal |
| null/undefined | 不显示 | — | — |

**位置：** BottomRow 中 `footer` 和 `createdAt` 之间，与 hostname/日期同行，不增加卡片高度

**CompactView：** 用纯色圆点 (size-2) 替代完整 badge，节省空间

### 1.2 处理状态叠加层 (ProcessingStatusOverlay)

**改什么：** 在卡片图片区域叠加半透明状态条，仅非 success 状态时显示

**改动文件：**
- 新建 `apps/web/components/dashboard/bookmarks/ProcessingStatusOverlay.tsx`
- 修改 `BookmarkLayoutAdaptingCard.tsx` — GridView 图片区域集成

**状态逻辑：**
```
全部 success → 不显示任何东西
有 pending → "处理中..." + Loader2 旋转图标（白色，底部渐变叠加）
有 failure → "部分失败" + AlertCircle 图标（红色）
```

**位置：** GridView 图片 div 底部，`bg-gradient-to-t from-black/60` 叠加层

**ListView/CompactView：** 缩略图右下角小圆点 + tooltip

**复用现有工具函数：**
- `packages/shared/bookmarkUtils.ts` — `isBookmarkStillCrawling()`, `isBookmarkStillTagging()`, `isBookmarkStillSummarizing()`
- 已有轮询刷新机制（1s/10s/60s 间隔），状态更新自动生效

---

## Phase 2: P1 — 来源筛选 + 采集统计

### 2.1 来源筛选 Chips (SourceFilterChips)

**方案：Chip 筛选条**（非 Tab、非 Dropdown）

理由：
- Tab 栏放不下 8 个来源，且暗示互斥切换
- Dropdown 操作步骤多，无法一眼看到筛选状态
- Chip 可视化展示所有选项，支持状态一目了然

**改动文件：**
- 新建 `apps/web/components/dashboard/bookmarks/SourceFilterChips.tsx`
- 修改 `Bookmarks.tsx` — 在列表上方渲染

**筛选实现策略：复用搜索后端**

搜索解析器已支持 `source:` 限定符（`searchQueryParser.ts` 第 236-252 行）。点击 chip 时注入 `source:extension` 查询到 SearchInput，跳转搜索页。

**备选方案（如需留在采集页内）：** 后端 `getBookmarks` 新增可选 `source` 参数
- `packages/shared/types/bookmarks.ts` — `zGetBookmarksRequestSchema` 增加 `source`
- `packages/trpc/models/bookmarks.ts` — `loadMulti` 增加 WHERE 条件

### 2.2 采集健康统计 (CollectionStatsRow)

**改什么：** 采集页顶部显示一行统计摘要

```
1,247 条收藏 | 插件 823 | RSS 201 | 手机 89 | 导入 134
```

**实现方式：** 新增轻量 tRPC endpoint `bookmarks.getSourceStats`
- 后端：`SELECT source, COUNT(*) FROM bookmarks WHERE userId = ? GROUP BY source`
- 前端：从 `UpdatableBookmarksGrid` 已加载 pages 聚合近似值（v1），精确计数（v2）

---

## Phase 3: P2 — 布局优化 + 增强

### 3.1 EditorCard 提取到 header 区域

**改什么：** 将手动输入框从 Masonry grid 内部移出，作为全宽独立区域

**改动文件：**
- `BookmarksGrid.tsx` — 移除 EditorCard 内嵌逻辑
- `Bookmarks.tsx` — 在 UpdatableBookmarksGrid 上方渲染 EditorCard
- `EditorCard.tsx` — 调整为全宽样式，增加能力提示标签（链接识别/图片粘贴）

### 3.2 RSS 快捷管理入口

**改什么：** 来源筛选栏 RSS chip 旁显示订阅数 badge，点击展开 popover

**Popover 内容：** 各 RSS 源名称 + 最近同步状态 + "管理订阅" 链接 + "立即抓取" 按钮

**复用：** `api.feeds.list` query + `api.feeds.fetchNow` mutation

### 3.3 失败重试

**改什么：** 失败状态指示器（P0 中已加）变为可点击，弹出重试操作

**复用：** `recrawlBookmark` mutation（已存在）

### 3.4 空状态重设计

**改什么：** 替换 NoBookmarksBanner 为引导式空状态，按来源展示 4 个快速入门卡片

---

## 新增/修改文件清单

### 新建
| 文件 | Phase |
|------|-------|
| `apps/web/components/dashboard/bookmarks/SourceBadge.tsx` | P0 |
| `apps/web/components/dashboard/bookmarks/ProcessingStatusOverlay.tsx` | P0 |
| `apps/web/components/dashboard/bookmarks/SourceFilterChips.tsx` | P1 |
| `apps/web/components/dashboard/bookmarks/CollectionStatsRow.tsx` | P1 |
| `apps/web/components/dashboard/bookmarks/CollectionHeader.tsx` | P2 |

### 修改
| 文件 | 改动 | Phase |
|------|------|-------|
| `BookmarkLayoutAdaptingCard.tsx` | BottomRow 加 SourceBadge + 图片区加 StatusOverlay | P0 |
| `Bookmarks.tsx` | 加 CollectionHeader / EditorCard 提取 | P1/P2 |
| `BookmarksGrid.tsx` | 移除 EditorCard 内嵌 | P2 |
| `NoBookmarksBanner.tsx` | 引导式空状态 | P2 |
| `packages/trpc/routers/bookmarks.ts` | 新增 getSourceStats endpoint | P1 |
| `packages/shared/types/bookmarks.ts` | getBookmarks schema 加 source 参数（备选） | P1 |

---

## 验证方案

1. **Phase 1 验证：** 在浏览器中打开采集页，确认每张卡片底部显示来源图标；添加一个新书签后观察"处理中"状态条出现并自动消失
2. **Phase 2 验证：** 点击来源筛选 chip，确认列表即时过滤；统计数字与实际数据一致
3. **Typecheck：** 每个 Phase 完成后运行 `pnpm typecheck`
4. **手动测试：** 4 种布局模式（masonry/grid/list/compact）均需验证
