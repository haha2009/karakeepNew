# 采集统计页面 — 技术设计文档

> 基于 PRD (`docs/internal/product/04-stats-page-prd.md`) 产出的深模块技术架构设计。

## 1. 设计原则

| 原则 | 实践 |
|------|------|
| **深模块** | 一个小接口（输入 userId，输出 StatsSnapshot）背后隐藏全部聚合逻辑 |
| **服务端计算** | 所有统计指标由后端精确计算，前端纯展示 |
| **灵活性** | 通过 optional 字段扩展，新增指标不破坏现有调用者 |
| **可测试** | 模块接受 DB 注入，用 in-memory SQLite 即可完整测试 |

## 2. 模块架构

```
                  ┌──────────────────────────────────┐
                  │        StatsModule (Deep)        │
                  │                                  │
                  │  Interface: { getStats(userId) } │
                  │  ───────────────────────────────  │
                  │  Implementation:                  │
                  │    ├─ BookmarkCounter             │
                  │    ├─ HeatmapCollector            │
                  │    ├─ DomainExtractor               │
                  │    ├─ StreakCalculator             │
                  │    └─ TypeClassifier              │
                  └──────────────┬───────────────────┘
                                 │
               ┌─────────────────┼─────────────────┐
               │                 │                   │
         ┌─────┴─────┐   ┌──────┴──────┐   ┌───────┴──────┐
         │ getStats  │   │ tags.list   │   │ Top Tags    │
         │ (tRPC)    │   │ (tRPC)      │   │ (extension) │
         └───────────┘   └─────────────┘   └──────────────┘
               │
               ▼
        ┌─────────────┐
        │  Frontend   │  ← 纯展示，不做计算
        │  StatsPage  │
        └─────────────┘
```

## 3. 接口定义

### 3.1 StatsModule — 核心深模块

```typescript
interface StatsModule {
  getStats(userId: string): Promise<StatsSnapshot>;
}

interface StatsSnapshot {
  // === 基础指标 ===
  todayCount: number;           // 今日采集量 (UTC 零点至今)
  totalCount: number;           // 累计采集总量
  usageDays: number;            // 有采集记录的天数
  favouritedCount: number;      // 收藏数 (favourited=true)
  currentMonthCount: number;    // 当月采集量

  // === 趋势指标 ===
  avgPerDay: number;            // 日均采集量 (totalCount / usageDays, 保留 1 位)
  longestStreak: number;        // 最长连续采集天数

  // === 分布数据 ===
  typeDistribution: {           // 内容类型分布
    link: number;
    text: number;
    asset: number;
  };
  topDomains: Array<{           // 热门域名 Top5
    domain: string;
    count: number;
  }>;
  domainDiversity: number;      // 唯一域名总数

  // === 标签指标 ===
  tagCount: number;             // 使用的标签总数

  // === 热力图 ===
  heatmapData: Array<{          // 近 6 个月每日数据
    date: string;               // "YYYY-MM-DD"
    count: number;
  }>;
}
```

**深度分析**:

- 接口: 1 个方法，1 个参数
- 实现: 5 个 SQL 查询 + 3 个纯计算函数
- 调用者只需要知道: `getStats(userId) → StatsSnapshot`
- 所有派生指标 (avgPerDay, longestStreak, typeDistribution) 隐藏在后

### 3.2 TagsStatsModule — 标签统计（可选扩展）

```typescript
interface TagsStatsModule {
  getTopTags(userId: string, limit: number): Promise<TagUsage[]>;
}

interface TagUsage {
  id: string;
  name: string;
  count: number;
}
```

**理由**: 标签统计独立于基础统计，使用现有 `tags.list?sortBy=usage` 即可，不需要合并到 StatsModule 中。保持单一职责。

## 4. SQL 查询设计

### 4.1 查询合并策略

当前实现有 5 个独立 SQL 查询。优化为 **5 个查询**（并行执行）:

| 查询 | 覆盖指标 | SQL 策略 |
|------|----------|----------|
| **Query A: 书签计数** | todayCount, totalCount, favouritedCount, currentMonthCount, usageDays | 单个 `SELECT` + conditional `SUM` |
| **Query B: 类型分布** | typeDistribution | GROUP BY type |
| **Query C: 域名数据** | topDomains, domainDiversity | LEFT JOIN bookmarkLinks，应用层解析域名 |
| **Query D: 热力图** | heatmapData, longestStreak | 按日 GROUP BY（复用现有逻辑） |
| **Query E: 标签计数** | tagCount | COUNT DISTINCT tagId |

### 4.2 Query A — 书签计数（合并版）

```sql
SELECT
  COUNT(*) AS totalCount,
  SUM(CASE WHEN createdAt > :startOfToday THEN 1 ELSE 0 END) AS todayCount,
  SUM(CASE WHEN favourited = 1 THEN 1 ELSE 0 END) AS favouritedCount,
  SUM(CASE WHEN strftime('%Y-%m', createdAt / 1000, 'unixepoch') = :currentMonth THEN 1 ELSE 0 END) AS currentMonthCount,
  COUNT(DISTINCT strftime('%Y-%m-%d', createdAt / 1000, 'unixepoch')) AS usageDays
FROM bookmarks
WHERE userId = :userId
```

**优势**: 一次表扫描获取 5 个指标，替代原来 3 次独立查询。

### 4.3 Query B — 类型分布

```sql
SELECT type, COUNT(*) AS count
FROM bookmarks
WHERE userId = :userId
GROUP BY type
```

### 4.4 Query C — 域名数据

```sql
-- Top 5 URL（域名在应用层解析）
SELECT bl.url, COUNT(*) AS count
FROM bookmarkLinks bl
INNER JOIN bookmarks b ON b.id = bl.id
WHERE b.userId = :userId
GROUP BY bl.url
ORDER BY count DESC
LIMIT 5

-- 唯一域名总数
SELECT COUNT(DISTINCT bl.url) AS domainDiversity
FROM bookmarkLinks bl
INNER JOIN bookmarks b ON b.id = bl.id
WHERE b.userId = :userId
```

**注意**: SQLite 没有 `URL_HOST()` 函数。域名提取在应用层用 JS `new URL(url).hostname` 处理，更准确且处理 edge case（端口、路径等）。

### 4.5 Query D — 热力图（保持不变）

```sql
SELECT
  strftime('%Y-%m-%d', createdAt / 1000, 'unixepoch') AS day,
  COUNT(*) AS count
FROM bookmarks
WHERE userId = :userId AND createdAt > :sixMonthsAgo
GROUP BY day
ORDER BY day
```

### 4.6 Query E — 标签计数

```sql
SELECT count(distinct tagId) AS count
FROM tagsOnBookmarks
INNER JOIN bookmarks ON bookmarks.id = tagsOnBookmarks.bookmarkId
WHERE bookmarks.userId = :userId
```

## 5. 实现架构

### 5.1 文件结构

```
packages/stats/                          ← 新包（深模块）
├── src/
│   ├── module.ts                        ← StatsModule 接口 + 实现
│   ├── types.ts                         ← StatsSnapshot schema
│   ├── calculators.ts                   ← 纯计算函数 (streak, avg)
│   └── index.ts                         ← 公开 API
├── test/
│   ├── module.test.ts                   ← 集成测试 (in-memory SQLite)
│   └── calculators.test.ts              ← 纯函数单元测试
└── package.json
```

**备选方案**: 如果不创建新包，可以放在 `packages/trpc/src/modules/stats.ts`。但独立包更清晰，且可被其他服务（workers、CLI）复用。

### 5.2 核心实现

```typescript
// packages/stats/src/module.ts

import { z } from "zod";
import { sql, eq, and, gt } from "drizzle-orm";
import type { DB } from "@karakeep/db/drizzle";
import { bookmarks, bookmarkLinks, tagsOnBookmarks } from "@karakeep/db/schema";

// ── Schema ──
export const zStatsSnapshotSchema = z.object({
  todayCount: z.number().int().nonnegative(),
  totalCount: z.number().int().nonnegative(),
  usageDays: z.number().int().nonnegative(),
  favouritedCount: z.number().int().nonnegative(),
  currentMonthCount: z.number().int().nonnegative(),
  avgPerDay: z.number().nonnegative(),
  longestStreak: z.number().int().nonnegative(),
  typeDistribution: z.object({
    link: z.number().int().nonnegative(),
    text: z.number().int().nonnegative(),
    asset: z.number().int().nonnegative(),
  }),
  topDomains: z.array(z.object({
    domain: z.string(),
    count: z.number().int().nonnegative(),
  })),
  domainDiversity: z.number().int().nonnegative(),
  tagCount: z.number().int().nonnegative(),
  heatmapData: z.array(z.object({
    date: z.string(),
    count: z.number().int().nonnegative(),
  })),
});

export type StatsSnapshot = z.infer<typeof zStatsSnapshotSchema>;

// ── Interface ──
export interface StatsModule {
  getStats(userId: string): Promise<StatsSnapshot>;
}

// ── Implementation ──
export function createStatsModule(db: DB): StatsModule {
  return {
    async getStats(userId: string): Promise<StatsSnapshot> {
      const now = new Date();
      const startOfToday = new Date(
        Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
      );
      const currentMonth = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`;
      const sixMonthsAgo = new Date();
      sixMonthsAgo.setUTCDate(1);
      sixMonthsAgo.setUTCMonth(sixMonthsAgo.getUTCMonth() - 6);
      sixMonthsAgo.setUTCHours(0, 0, 0, 0);

      // 并行执行 5 个查询
      const [counter, typeDist, domainTop, domainAll, heatmap, tagCount] = await Promise.all([
        // Query A: 基础计数
        db.select({
          totalCount: sql<number>`COUNT(*)`,
          todayCount: sql<number>`SUM(CASE WHEN ${bookmarks.createdAt} > ${startOfToday} THEN 1 ELSE 0 END)`,
          favouritedCount: sql<number>`SUM(CASE WHEN ${bookmarks.favourited} = 1 THEN 1 ELSE 0 END)`,
          currentMonthCount: sql<number>`SUM(CASE WHEN strftime('%Y-%m', ${bookmarks.createdAt} / 1000, 'unixepoch') = ${currentMonth} THEN 1 ELSE 0 END)`,
          usageDays: sql<number>`COUNT(DISTINCT strftime('%Y-%m-%d', ${bookmarks.createdAt} / 1000, 'unixepoch'))`,
        }).from(bookmarks).where(eq(bookmarks.userId, userId)),

        // Query B: 类型分布
        db.select({
          type: bookmarks.type,
          count: sql<number>`COUNT(*)`,
        }).from(bookmarks).where(eq(bookmarks.userId, userId)).groupBy(bookmarks.type),

        // Query C1: 域名 Top5 URL
        db.select({
          url: bookmarkLinks.url,
          count: sql<number>`COUNT(*)`,
        })
          .from(bookmarkLinks)
          .innerJoin(bookmarks, eq(bookmarks.id, bookmarkLinks.id))
          .where(eq(bookmarks.userId, userId))
          .groupBy(bookmarkLinks.url)
          .orderBy(sql`COUNT(*) DESC`)
          .limit(5),

        // Query C2: 所有 URL（用于域名多样性）
        db.select({ url: bookmarkLinks.url })
          .from(bookmarkLinks)
          .innerJoin(bookmarks, eq(bookmarks.id, bookmarkLinks.id))
          .where(eq(bookmarks.userId, userId)),

        // Query D: 热力图
        db.select({
          day: sql<string>`strftime('%Y-%m-%d', ${bookmarks.createdAt} / 1000, 'unixepoch')`,
          count: sql<number>`COUNT(*)`,
        })
          .from(bookmarks)
          .where(and(eq(bookmarks.userId, userId), gt(bookmarks.createdAt, sixMonthsAgo)))
          .groupBy(sql`strftime('%Y-%m-%d', ${bookmarks.createdAt} / 1000, 'unixepoch')`)
          .orderBy(sql`strftime('%Y-%m-%d', ${bookmarks.createdAt} / 1000, 'unixepoch')`),

        // Query E: 标签数
        db.select({ count: sql<number>`count(distinct ${tagsOnBookmarks.tagId})` })
          .from(tagsOnBookmarks)
          .innerJoin(bookmarks, eq(bookmarks.id, tagsOnBookmarks.bookmarkId))
          .where(eq(bookmarks.userId, userId)),
      ]);

      const c = counter[0] ?? { totalCount: 0, todayCount: 0, favouritedCount: 0, currentMonthCount: 0, usageDays: 0 };

      // 类型分布
      const typeDistribution = { link: 0, text: 0, asset: 0 };
      for (const row of typeDist) {
        if (row.type in typeDistribution) {
          typeDistribution[row.type as keyof typeof typeDistribution] = row.count;
        }
      }

      // 域名: JS 层解析
      const domainCounts = new Map<string, number>();
      for (const row of domainTop) {
        const domain = extractDomain(row.url);
        if (domain) {
          domainCounts.set(domain, (domainCounts.get(domain) ?? 0) + row.count);
        }
      }
      const topDomains = Array.from(domainCounts.entries())
        .sort((a, b) => b[1] - a[1])
        .slice(0, 5)
        .map(([domain, count]) => ({ domain, count }));

      // 域名多样性
      const uniqueDomains = new Set(domainAll.map((r) => extractDomain(r.url)));
      const domainDiversity = uniqueDomains.size;

      // 热力图
      const heatmapData = heatmap.map((h) => ({ date: h.day, count: h.count }));

      // 派生计算
      const avgPerDay = c.usageDays > 0
        ? Math.round((c.totalCount / c.usageDays) * 10) / 10
        : 0;
      const longestStreak = calculateLongestStreak(heatmapData);
      const tagCountResult = tagCount[0]?.count ?? 0;

      return zStatsSnapshotSchema.parse({
        todayCount: c.todayCount,
        totalCount: c.totalCount,
        usageDays: c.usageDays,
        favouritedCount: c.favouritedCount,
        currentMonthCount: c.currentMonthCount,
        avgPerDay,
        longestStreak,
        typeDistribution,
        topDomains,
        domainDiversity,
        tagCount: tagCountResult,
        heatmapData,
      });
    },
  };
}

// ── Pure Functions ──

function extractDomain(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
}

function calculateLongestStreak(heatmapData: Array<{ date: string; count: number }>): number {
  if (heatmapData.length === 0) return 0;

  const activeDays = new Set(
    heatmapData.filter((d) => d.count > 0).map((d) => d.date),
  );

  let longestStreak = 0;
  let currentStreak = 0;
  let prevDate: Date | null = null;

  for (const day of Array.from(activeDays).sort()) {
    const date = new Date(day + "T00:00:00Z");
    if (prevDate) {
      const diffDays = Math.round((date.getTime() - prevDate.getTime()) / 86400000);
      if (diffDays === 1) {
        currentStreak++;
      } else {
        longestStreak = Math.max(longestStreak, currentStreak);
        currentStreak = 1;
      }
    } else {
      currentStreak = 1;
    }
    prevDate = date;
  }
  longestStreak = Math.max(longestStreak, currentStreak);

  return longestStreak;
}
```

### 5.3 tRPC 层（薄适配层）

```typescript
// packages/trpc/routers/bookmarks.ts — getStats 改造

import { createStatsModule } from "@karakeep/stats";

// 在 router 工厂函数中注入
export const createBookmarkRouter = (deps: { db: DB; ... }) => {
  const statsModule = createStatsModule(deps.db);

  return trpc.router({
    getStats: bookmarksProcedure
      .output(zStatsSnapshotSchema)
      .query(async ({ ctx }) => {
        return statsModule.getStats(ctx.user.id);
      }),
    // ...
  });
};
```

**原则**: tRPC 层只做 auth + delegation，不包含任何业务逻辑。

## 6. 前端适配

### 6.1 前端只需要做映射

```typescript
// BookmarkStatsPage.tsx — 数据消费

const { data: stats } = useQuery(api.bookmarks.getStats.queryOptions());

// 直接映射，不做计算
const metricCards = [
  { label: "今日采集量", value: stats?.todayCount ?? 0 },
  { label: "收藏数", value: stats?.favouritedCount ?? 0 },
  { label: "累计采集量", value: stats?.totalCount ?? 0 },
  { label: "使用天数", value: stats?.usageDays ?? 0 },
];

// 内容分布 — 直接消费
const typeDistribution = stats?.typeDistribution ?? { link: 0, text: 0, asset: 0 };

// 热门域名 — 直接消费
const topDomains = stats?.topDomains ?? [];
```

### 6.2 删除的前端计算

以下逻辑从前端移除，由后端替代:

| 删除 | 替代 |
|------|------|
| `monthBookmarks.length` → 收藏数 | `stats.favouritedCount` |
| `typeDistribution` 从 `allBookmarks.reduce` 计算 | `stats.typeDistribution` |
| `topDomains` 从 `allBookmarks` 遍历计算 | `stats.topDomains` |
| `currentMonthCount` 前端过滤 | `stats.currentMonthCount` |

### 6.3 当月采集量不再需要

日历组件的"当月 N 条"文案改为消费 `stats.currentMonthCount`。

日历格子的高亮仍需要按日统计，但数据从 `heatmapData` 中过滤当月日期获取:

```typescript
const bookmarksPerDay = useMemo(() => {
  const map = new Map<string, number>();
  for (const d of stats?.heatmapData ?? []) {
    if (d.date.startsWith(format(currentMonth, "yyyy-MM"))) {
      map.set(d.date, d.count);
    }
  }
  return map;
}, [stats?.heatmapData, currentMonth]);
```

## 7. 数据库索引

现有索引已覆盖所有查询:

| 查询 | 使用索引 |
|------|----------|
| Query A (基础计数) | `bookmarks_userId_idx` |
| Query B (类型) | `bookmarks_userId_idx` (filter) + type 列 |
| Query C (域名) | `bookmarks_userId_idx` (via JOIN) |
| Query D (热力图) | `bookmarks_userId_createdAt_id_idx` |
| Query E (标签) | `tagsOnBookmarks_bookmarkId_idx` + `bookmarks_userId_idx` |

**不需要新增索引**。

## 8. 测试设计

### 8.1 单元测试 — 纯函数

```typescript
describe("calculateLongestStreak", () => {
  it("空数据返回 0", () => {
    expect(calculateLongestStreak([])).toBe(0);
  });

  it("连续 5 天", () => {
    const data = [
      { date: "2026-06-01", count: 1 },
      { date: "2026-06-02", count: 3 },
      { date: "2026-06-03", count: 2 },
      { date: "2026-06-04", count: 1 },
      { date: "2026-06-05", count: 4 },
    ];
    expect(calculateLongestStreak(data)).toBe(5);
  });

  it("中断后取最长", () => {
    const data = [
      { date: "2026-06-01", count: 1 },
      { date: "2026-06-02", count: 1 },
      { date: "2026-06-04", count: 1 },
      { date: "2026-06-05", count: 1 },
      { date: "2026-06-06", count: 1 },
      { date: "2026-06-07", count: 1 },
    ];
    expect(calculateLongestStreak(data)).toBe(4);
  });
});

describe("extractDomain", () => {
  it("基本 URL", () => {
    expect(extractDomain("https://example.com/path")).toBe("example.com");
  });

  it("带 www", () => {
    expect(extractDomain("https://www.example.com")).toBe("example.com");
  });

  it("无效 URL", () => {
    expect(extractDomain("not-a-url")).toBe("");
  });
});
```

### 8.2 集成测试 — StatsModule

```typescript
describe("StatsModule.getStats", () => {
  it("返回完整的 StatsSnapshot", async () => {
    // ... setup test data ...
    const stats = await module.getStats("user1");
    expect(stats.todayCount).toBe(2);
    expect(stats.totalCount).toBe(3);
    expect(stats.favouritedCount).toBe(2);
    expect(stats.usageDays).toBe(2);
    expect(stats.typeDistribution).toEqual({ link: 2, text: 1, asset: 0 });
  });

  it("空用户返回全零", async () => {
    const stats = await module.getStats("empty-user");
    expect(stats.totalCount).toBe(0);
    expect(stats.avgPerDay).toBe(0);
    expect(stats.longestStreak).toBe(0);
  });

  it("连续天数计算正确", async () => {
    // 6/1, 6/2, 6/3, 6/5
    const stats = await module.getStats("streak-user");
    expect(stats.longestStreak).toBe(3); // 6/1-6/3
    expect(stats.usageDays).toBe(4);
  });
});
```

## 9. 变更清单

### 新增文件

| 文件 | 说明 |
|------|------|
| `packages/stats/package.json` | 包声明 |
| `packages/stats/src/module.ts` | StatsModule 接口 + 实现 |
| `packages/stats/src/types.ts` | StatsSnapshot zod schema |
| `packages/stats/src/calculators.ts` | extractDomain, calculateLongestStreak |
| `packages/stats/src/index.ts` | 公开 API |
| `packages/stats/test/module.test.ts` | 集成测试 |
| `packages/stats/test/calculators.test.ts` | 单元测试 |

### 修改文件

| 文件 | 变更 |
|------|------|
| `packages/shared/types/bookmarks.ts` | `zBookmarkStatsSchema` 扩展新字段 |
| `packages/trpc/routers/bookmarks.ts` | `getStats` 改为委托 StatsModule |
| `apps/web/components/dashboard/bookmarks/BookmarkStatsPage.tsx` | 消费新字段，删除前端计算逻辑 |

### 无变更

| 文件 | 原因 |
|------|------|
| `Heatmap.tsx` | 不受影响，props 不变 |
| `BookmarkListItem.tsx` | 不受影响 |
| 数据库 schema | 不需要新增表或列 |

## 10. 风险与权衡

| 风险 | 缓解 |
|------|------|
| Query C2 域名多样性全量扫描 | 用户书签量通常 <10k，URL 去重很快；未来可缓存 |
| 5 个并行查询增加 DB 压力 | SQLite 本地 I/O，并行查询 <50ms；连接池不适用 SQLite |
| 新包增加构建复杂度 | Turborepo 天然支持，只在 `packages/trpc` 添加依赖 |
| longestStreak 仅基于 heatmapData (6个月) | 如果用户在 6 个月前有更长的 streak 则不计入；可接受，因为 UI 已标注"近6个月" |
