# 采集统计页面 — 需求规格文档

> 本文档定义「采集统计」页面（`/dashboard/stats`）的功能需求、数据规范、组件架构和后续迭代方向。

## 1. 页面定位

采集统计页面是用户书签数据的可视化中枢，帮助用户了解自己的收藏行为模式、内容分布和使用习惯。

**核心问题**：用户在收藏了什么？收藏的节奏如何？内容偏好是什么？

## 2. 页面结构

```
┌─────────────────────────────────────────────────────────┐
│  Header: 采集                              [+ 添加按钮]  │
├─────────────────────────────────────────────────────────┤
│  [今日采集量]  [收藏数]  [累计采集量]  [使用天数]        │
├─────────────────────────────────────────────────────────┤
│  ┌──────────┐ ┌──────────────────┐ ┌─────────────────┐  │
│  │ 日历     │ │  采集热力图      │ │ 内容分布        │  │
│  │ (月度)   │ │  (近6个月)       │ │ (链接/笔记/资产) │  │
│  │          │ │                  │ ├─────────────────┤  │
│  │          │ │                  │ │ 热门域名 Top5   │  │
│  └──────────┘ └──────────────────┘ └─────────────────┘  │
├─────────────────────────────────────────────────────────┤
│  全部采集 (N)                                            │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐                   │
│  │ Card │ │ Card │ │ Card │ │ Card │  ← 4列网格        │
│  └──────┘ └──────┘ └──────┘ └──────┐                   │
│                                    [加载更多]            │
└─────────────────────────────────────────────────────────┘
```

## 3. 数据源

### 3.1 getStats 接口

**端点**: `bookmarks.getStats` (tRPC query)

| 字段 | 类型 | 说明 | UI 映射 |
|------|------|------|---------|
| `todayCount` | `number` | 今日采集量（UTC 零点至今） | 指标卡片 #1 |
| `totalCount` | `number` | 累计采集总量 | 指标卡片 #3 |
| `usageDays` | `number` | 有采集记录的天数 | 指标卡片 #4 |
| `tagCount` | `number` | 标签使用数量（可选，默认 0） | 指标卡片 #2（待决策） |
| `heatmapData` | `{ date: string, count: number }[]` | 近 6 个月每日采集数 | 热力图组件 |

### 3.2 getBookmarks 无限滚动

**端点**: `bookmarks.getBookmarks.infiniteQuery`

**请求参数**:
```typescript
{
  archived: false,
  includeContent: false,
  sortOrder: "desc",
  useCursorV2: true,
}
```

**响应**:
```typescript
{
  bookmarks: ZBookmark[],
  nextCursor: { createdAt: Date, id: string } | null,
}
```

### 3.3 派生数据（前端计算）

| 数据 | 计算方式 | UI 映射 |
|------|----------|---------|
| 当月采集量 | `allBookmarks.filter(isSameMonth(currentMonth))` | 指标卡片 #2 / 日历 |
| 内容类型分布 | `allBookmarks.reduce(count by type)` | 内容分布卡片 |
| 热门域名 Top5 | `allBookmarks.filter(LINK).count(domain).sort.desc.slice(5)` | 热门域名卡片 |

## 4. 组件架构

```
BookmarkStatsPage.tsx          ← 页面主组件 (container)
├── Heatmap.tsx                ← 近6个月热力图 (pure presentational)
├── BookmarkListItem.tsx       ← 书签卡片 (pure presentational)
├── AddDropdownMenu.tsx        ← 添加按钮 (已有)
└── Card / CardContent          ← shadcn/ui 基础组件
```

### 4.1 BookmarkStatsPage

**职责**: 数据获取、布局编排、派生数据计算

**状态**:
- `currentMonth: Date` — 日历当前浏览月份

**数据流**:
```
api.bookmarks.getStats → stats (todayCount, totalCount, usageDays, heatmapData)
api.bookmarks.getBookmarks.infinite → allBookmarks (desc, cursor pagination)
                                    → monthBookmarks (当月过滤)
                                    → typeDistribution (类型统计)
                                    → topDomains (域名统计)
```

### 4.2 Heatmap

**Props**: `{ data: { date: string, count: number }[] }`

**视觉规范**:
- 展示近 6 个月，按周列排列
- 颜色: 绿色系 (`emerald-200` → `emerald-400` → `emerald-500` → `emerald-700`)
- 今日标记: `ring-1.5 ring-foreground`
- 月份标签: 按"主导月份"算法定位，最小间隔 2 列
- 悬浮提示: 显示日期 + 采集数量
- 统计行: 总计 / 活跃天数 / 峰值

### 4.3 BookmarkListItem

**Props**: `{ bookmark: ZBookmark }`

**布局**: 左图右文 + 底部信息条

**交互**:
- 点击卡片 → 跳转到 `/dashboard/preview/{id}`
- Star 按钮 → 切换收藏状态（使用 `useUpdateBookmark` hook）
- Hover: 微上浮 + 阴影 + 图片缩放

**底部条**:
- 背景: `bg-black/[0.1]`，hover `bg-black/[0.2]`
- 内容: 域名 (Globe icon) + 相对时间
- 高度: 24px (`h-6`)

## 5. 设计规范

### 5.1 色彩

| 用途 | 颜色 | Tailwind 类 |
|------|------|-------------|
| 页面背景 | 微灰 | `bg-muted/20` |
| 卡片背景 | 主题色 | `bg-card` |
| 热力图 0 | 微灰 | `bg-muted/30` |
| 热力图 1-2 | 浅绿 | `bg-emerald-200` |
| 热力图 3-5 | 中绿 | `bg-emerald-400` |
| 热力图 6-10 | 深绿 | `bg-emerald-500` |
| 热力图 11+ | 墨绿 | `bg-emerald-700` |
| 底部条 | 黑色 10% | `bg-black/[0.1]` |
| 底部条 hover | 黑色 20% | `group-hover:bg-black/[0.2]` |

### 5.2 图标

- 所有 icon 统一使用 `text-foreground`（黑色/主题色）
- 不使用渐变、不使用彩色 icon
- 图标库: lucide-react

### 5.3 排版

| 元素 | 字号 | 字重 |
|------|------|------|
| 页面标题 | `text-base` (16px) | `font-semibold` |
| 指标数值 | `text-xl` (20px) | `font-bold` |
| 指标标签 | `text-[11px]` | normal |
| 卡片标题 | `text-[13.5px]` | `font-medium` |
| 预览文字 | `text-[11.5px]` | normal |
| 底部信息 | `text-[11px]` | normal |
| 辅助文字 | `text-[10px]` | normal |

### 5.4 间距

| 区域 | 间距 |
|------|------|
| 页面 padding | `p-4 lg:p-6` |
| 卡片间距 | `gap-3` |
| 网格间距 | `gap-4` |
| 指标卡片 | `grid-cols-2 lg:grid-cols-4` |
| 书签网格 | `grid-cols-1 sm:grid-cols-2 lg:grid-cols-4` |

## 6. 响应式断点

| 断点 | 布局 |
|------|------|
| < 640px | 单列指标卡片，单列书签 |
| 640px - 1024px | 2 列指标卡片，2 列书签 |
| >= 1024px | 4 列指标卡片，12 列网格 (日历3 + 热力图5 + 洞察4)，4 列书签 |

## 7. 交互规范

### 7.1 日历月份切换

- 左箭头: 切换到上一月（无限制）
- 右箭头: 切换到下一月（不能超过当前月）
- 当前月时右箭头禁用 (`disabled` + `opacity-30`)

### 7.2 热力图交互

- Hover 格子: 显示 tooltip（日期 + 采集数）
- 今日格子: 显示 ring 标记
- 无动画（热力图格子不做 transition）

### 7.3 书签列表

- 无限滚动: "加载更多"按钮触发 `fetchNextPage()`
- 加载中: 按钮显示 spinner
- 无数据: 显示空状态（虚线边框 + Library icon + 文案）

### 7.4 收藏按钮

- 点击切换收藏/取消收藏
- 乐观更新: 立即更新本地状态，后台同步
- 已收藏: 琥珀色填充 (`fill-amber-400` + glow)
- 未收藏: 灰色轮廓

## 8. 待完善 & 后续迭代

### 8.1 当前已知问题

| # | 问题 | 优先级 | 说明 |
|---|------|--------|------|
| 1 | 收藏数指标不准确 | P1 | 当前使用 `monthBookmarks.length`（当月采集数），不是真正的收藏数（favourited=true 的数量） |
| 2 | 日历热力图数据不完整 | P1 | 日历只展示当月数据，跨月切换时需要重新计算 |
| 3 | 内容分布基于已加载数据 | P2 | `typeDistribution` 和 `topDomains` 基于分页加载的 bookmarks，非全量统计 |
| 4 | 缺少标签统计模块 | P2 | `tagCount` 已返回但未在 UI 中展示 |
| 5 | 缺少平均/日均指标 | P3 | 可通过 `totalCount / usageDays` 计算 |
| 6 | 缺少连续采集天数 | P3 | 需要额外查询或扩展 getStats 接口 |

### 8.2 后续功能规划

| 功能 | 描述 | 依赖 |
|------|------|------|
| 标签云/Top标签 | 展示使用频率最高的标签 | `tags.list?sortBy=usage` |
| 采集趋势图 | 折线图展示采集量随时间变化 | 扩展 heatmapData 或新接口 |
| 域名详情页 | 点击域名展示该域名下所有书签 | 新页面 + 查询参数 |
| 数据导出 | 导出统计报告为 CSV/PDF | 新接口 + 前端导出逻辑 |
| 对比模式 | 选择两个时间段对比采集行为 | 时间选择器 + 对比算法 |

## 9. 文件清单

| 文件 | 路径 | 说明 |
|------|------|------|
| 页面主组件 | `apps/web/components/dashboard/bookmarks/BookmarkStatsPage.tsx` | 数据获取 + 布局 |
| 热力图 | `apps/web/components/dashboard/bookmarks/Heatmap.tsx` | 纯展示组件 |
| 书签卡片 | `apps/web/components/dashboard/bookmarks/BookmarkListItem.tsx` | 卡片展示 |
| 类型定义 | `packages/shared/types/bookmarks.ts` | zBookmarkStatsSchema |
| 后端路由 | `packages/trpc/routers/bookmarks.ts` | getStats 端点 |
