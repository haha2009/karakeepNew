# PRD: 采集统计页面需求完善

> 基于当前已实现的采集统计页面（`BookmarkStatsPage`），本文档定义需要修复的问题和后续迭代需求。

## Problem Statement

采集统计页面已完成基础重设计（极简风格、绿色热力图、卡片收藏按钮），但存在以下数据准确性问题：

1. **收藏数指标不准** — 当前使用当月采集数量代替收藏数（favourited=true 的数量）
2. **内容分布/热门域名数据不完整** — 基于分页加载的部分数据计算，非全量统计
3. **tagCount 未展示** — 后端已返回标签数量字段，UI 中未使用
4. **缺少日均指标** — 可通过已有数据推导但尚未展示
5. **缺少连续采集天数** — 需要计算最长连续有采集记录的天数

## Solution

分两个阶段推进：

- **Phase 1（数据准确性）**：修复现有指标的计算逻辑，确保数据正确
- **Phase 2（功能增强）**：添加标签统计、日均指标、连续天数等新维度

## User Stories

### Phase 1: 数据准确性修复

1. As a user, I want the "收藏数" metric card to show the actual number of favourited bookmarks, so that I can see how many items I've truly starred.

2. As a user, I want the content distribution chart to reflect ALL my bookmarks (not just the first page), so that the type breakdown is accurate.

3. As a user, I want the top domains list to be based on my entire collection, so that I get a true picture of where my bookmarks come from.

4. As a user, I want the calendar heatmap to show complete data for any month I navigate to, so that I'm not missing bookmarks that haven't been loaded yet.

5. As a user, I want the "当月采集量" to be computed from a dedicated monthly count query (not from filtering loaded pages), so that the number is always correct.

### Phase 2: 功能增强

6. As a user, I want to see my tag count prominently displayed, so that I know how many distinct tags I've created.

7. As a user, I want to see my average bookmarks per day, so that I can understand my collection habits.

8. As a user, I want to see my longest streak of consecutive days with at least one bookmark, so that I'm motivated to maintain my collection habit.

9. As a user, I want to see a "Top Tags" section showing my most frequently used tags, so that I can understand my tagging patterns.

10. As a user, I want the metric cards to show a brief comparison (e.g., "比上月 +5"), so that I can see trends at a glance.

11. As a user, I want to see domain diversity stats (number of unique domains), so that I understand how diverse my collection sources are.

12. As a user, I want to see a mini trend sparkline next to each metric card, so that I can see the metric's trajectory over recent months.

## Implementation Decisions

### Decision 1: 收藏数指标修复

**当前实现**: `monthBookmarks.length` — 当月已加载的书签数量
**修复方案**: 在 `getStats` 端点中新增 `favouritedCount` 字段，SQL 查询 `count(*) WHERE favourited = true`。前端直接消费该字段。

**理由**: 收藏数是全局指标，不应受当月过滤或分页影响。后端一次查询即可，无需前端计算。

### Decision 2: 内容分布与热门域名数据源

**当前实现**: 基于 `getBookmarks` 无限滚动已加载的页面数据
**修复方案**: 在 `getStats` 端点中新增以下聚合数据：

```typescript
// 新增返回字段
typeDistribution: {
  link: number;
  text: number;
  asset: number;
};
topDomains: Array<{ domain: string; count: number }>;
```

**SQL 策略**:
- `typeDistribution`: `GROUP BY content->>'type'`
- `topDomains`: `SELECT hostname, COUNT(*) FROM bookmarkLinks GROUP BY hostname ORDER BY COUNT(*) DESC LIMIT 5`

**理由**: 聚合查询在数据库层面完成，避免传输大量原始数据到前端再计算。一次请求即可获取全量统计。

### Decision 3: 当月采集量

**当前实现**: 前端过滤 `allBookmarks.filter(isSameMonth)`
**修复方案**: 在 `getStats` 端点中新增 `currentMonthCount` 字段，后端按当前月份过滤计数。

**理由**: 与收藏数同理，应从后端精确计算而非前端过滤。

### Decision 4: 新增统计字段

在 `zBookmarkStatsSchema` 中扩展：

```typescript
export const zBookmarkStatsSchema = z.object({
  todayCount: z.number().int().nonnegative(),
  totalCount: z.number().int().nonnegative(),
  usageDays: z.number().int().nonnegative(),
  tagCount: z.number().int().nonnegative().optional().default(0),
  // --- 新增 ---
  favouritedCount: z.number().int().nonnegative(),
  currentMonthCount: z.number().int().nonnegative(),
  avgPerDay: z.number().nonnegative(),          // totalCount / usageDays
  longestStreak: z.number().int().nonnegative(), // 最长连续天数
  typeDistribution: z.object({
    link: z.number().int().nonnegative(),
    text: z.number().int().nonnegative(),
    asset: z.number().int().nonnegative(),
  }),
  topDomains: z.array(z.object({
    domain: z.string(),
    count: z.number().int().nonnegative(),
  })),
  domainDiversity: z.number().int().nonnegative(), // 唯一域名总数
  heatmapData: z.array(zHeatmapDaySchema),
});
```

### Decision 5: 连续采集天数计算

**算法**: 从 `heatmapData` 中提取所有 `count > 0` 的日期，排序后遍历计算最长连续序列。

**实现位置**: 后端 SQL 查询。使用窗口函数或应用层计算。考虑到 `heatmapData` 已经包含近 6 个月每日数据，可在应用层计算 streak 后返回。

### Decision 6: 指标卡片布局更新

4 个指标卡片调整为：

| 位置 | 指标 | 数据来源 | 说明 |
|------|------|----------|------|
| #1 | 今日采集量 | `todayCount` | 不变 |
| #2 | 收藏数 | `favouritedCount` (新) | 真正的收藏数 |
| #3 | 累计采集量 | `totalCount` | 不变 |
| #4 | 使用天数 | `usageDays` | 不变 |

**后续可选项**（Phase 2 指标卡片区域扩展为 6 个）：
- #5: 日均采集 (`avgPerDay`)
- #6: 连续天数 (`longestStreak`)

### Decision 7: 内容分布卡片数据源

**当前**: 前端从 `allBookmarks` 计算
**修复**: 直接使用 `stats.typeDistribution`，不再依赖分页数据

### Decision 8: 热门域名卡片数据源

**当前**: 前端从 `allBookmarks` 计算
**修复**: 直接使用 `stats.topDomains`，不再依赖分页数据

### Decision 9: 标签统计模块

在 Insights 区域新增卡片：

- **标签总数**: 展示 `tagCount`
- **Top 5 标签**: 调用 `tags.list?sortBy=usage&limit=5` 获取使用频率最高的标签

**注意**: Top 标签需要额外的 tRPC 查询（`tags.list`），不在 `getStats` 中合并，避免该接口过于臃肿。

## Testing Decisions

### 测试策略

1. **getStats 端点单元测试**: 验证新增字段的正确性
   - `favouritedCount`: 创建不同收藏状态的书签，验证计数
   - `currentMonthCount`: 创建跨月书签，验证只计当月
   - `avgPerDay`: 验证 `totalCount / usageDays` 计算
   - `longestStreak`: 构造连续/不连续日期数据，验证最长连续计算
   - `typeDistribution`: 创建不同类型书签，验证分布计数
   - `topDomains`: 创建不同域名的链接书签，验证排序和限制
   - `domainDiversity`: 验证唯一域名计数

2. **组件测试**: 验证指标卡片显示正确数据
   - 使用 mock stats 数据渲染，验证各指标卡片的 label + value

3. **集成测试**: 端到端验证
   - 创建一批测试书签（跨月、跨类型、不同域名、部分收藏）
   - 访问统计页面，验证所有指标数值正确

### 测试优先原则

- 测试外部行为（用户看到什么），不测试实现细节
- 优先复用现有测试模式和工具（vitest + testing-library）
- 参考项目中已有的 tRPC router 测试作为模板

## Out of Scope

以下功能不在本 PRD 范围内，留作后续迭代：

- 标签云可视化（Tag Cloud）
- 采集趋势折线图（Sparkline / Chart）
- 时间段对比模式（选择两个时间段对比）
- 数据导出（CSV / PDF）
- 域名详情页（点击域名查看该域名下所有书签）
- 指标卡片的环比对比（"比上月 +5"）
- 移动端适配优化（当前已有基础响应式）

## Further Notes

- 后端变更集中在 `packages/trpc/routers/bookmarks.ts` 的 `getStats` 端点
- 类型变更集中在 `packages/shared/types/bookmarks.ts` 的 `zBookmarkStatsSchema`
- 前端变更集中在 `apps/web/components/dashboard/bookmarks/BookmarkStatsPage.tsx`
- 现有 `Heatmap.tsx` 和 `BookmarkListItem.tsx` 组件不需要修改
- 数据库不需要 schema 变更，所有新指标都从现有数据聚合计算
- 建议先实现 Phase 1（数据准确性修复），验证无误后再推进 Phase 2（功能增强）
