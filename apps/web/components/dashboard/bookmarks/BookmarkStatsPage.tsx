"use client";

import React, { useMemo, useState } from "react";
import {
  addDays,
  addMonths,
  endOfMonth,
  format,
  isSameDay,
  isSameMonth,
  startOfMonth,
  startOfWeek,
  subMonths,
} from "date-fns";
import { zhCN } from "date-fns/locale";
import {
  ArrowDownToLine,
  Bookmark,
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  Flame,
  Link2,
  Library,
  Timer,
  TrendingUp,
} from "lucide-react";
import { useTRPC } from "@karakeep/shared-react/trpc";
import { useInfiniteQuery, useQuery } from "@tanstack/react-query";

import Heatmap from "./Heatmap";
import BookmarkListItem from "./BookmarkListItem";
import AddDropdownMenu from "./AddDropdownMenu";
import { Card, CardContent } from "@/components/ui/card";
import { cn } from "@/lib/utils";

export default function BookmarkStatsPage() {
  const api = useTRPC();
  const [currentMonth, setCurrentMonth] = useState(new Date());

  const { data: stats, isLoading: statsLoading } = useQuery(
    api.bookmarks.getStats.queryOptions(),
  );

  const {
    data,
    fetchNextPage,
    hasNextPage,
    isFetchingNextPage,
    isLoading: bookmarksLoading,
  } = useInfiniteQuery(
    api.bookmarks.getBookmarks.infiniteQueryOptions(
      {
        archived: false,
        includeContent: false,
        sortOrder: "desc",
        useCursorV2: true,
      },
      {
        getNextPageParam: (lastPage) => lastPage.nextCursor,
      },
    ),
  );

  const allBookmarks = useMemo(
    () => data?.pages.flatMap((p) => p.bookmarks) ?? [],
    [data],
  );

  // Calendar
  const calendarDays = useMemo(() => {
    const monthStart = startOfMonth(currentMonth);
    const monthEnd = endOfMonth(currentMonth);
    const calStart = startOfWeek(monthStart, { weekStartsOn: 1 });
    const days: Date[] = [];
    let day = calStart;
    while (day <= monthEnd || days.length % 7 !== 0) {
      days.push(day);
      day = addDays(day, 1);
    }
    return days;
  }, [currentMonth]);

  const bookmarksPerDay = useMemo(() => {
    const map = new Map<string, number>();
    for (const d of stats?.heatmapData ?? []) {
      if (d.date.startsWith(format(currentMonth, "yyyy-MM"))) {
        map.set(d.date, d.count);
      }
    }
    return map;
  }, [stats?.heatmapData, currentMonth]);

  // Insights
  const typeDistribution = stats?.typeDistribution ?? {
    link: 0,
    text: 0,
    asset: 0,
  };
  const topDomains = stats?.topDomains ?? [];

  const prevMonth = () => setCurrentMonth(subMonths(currentMonth, 1));
  const nextMonth = () => {
    const next = addMonths(currentMonth, 1);
    if (isSameMonth(next, new Date()) || next < new Date()) {
      setCurrentMonth(next);
    }
  };
  const isCurrentMonth = isSameMonth(currentMonth, new Date());

  if (statsLoading || bookmarksLoading) {
    return (
      <div className="flex h-[60vh] items-center justify-center">
        <div className="size-8 animate-spin rounded-full border-2 border-primary border-t-transparent" />
      </div>
    );
  }

  return (
    <div className="flex w-full flex-col gap-5 rounded-r-lg bg-muted/20 p-4 lg:p-6">
      {/* ===== Header ===== */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="size-1.5 rounded-full bg-foreground" />
          <h1 className="text-base font-semibold tracking-tight">采集</h1>
        </div>
        <AddDropdownMenu />
      </div>

      {/* ===== Metric Cards ===== */}
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {[
          {
            label: "今日采集量",
            value: stats?.todayCount ?? 0,
            icon: TrendingUp,
          },
          {
            label: "收藏数",
            value: stats?.favouritedCount ?? 0,
            icon: CalendarDays,
          },
          {
            label: "累计采集量",
            value: stats?.totalCount ?? 0,
            icon: Library,
          },
          {
            label: "使用天数",
            value: stats?.usageDays ?? 0,
            unit: "天",
            icon: Flame,
          },
        ].map((card) => (
          <div
            key={card.label}
            className="flex items-center gap-3 rounded-xl border border-border/50 bg-card p-4 transition-colors hover:border-border"
          >
            <div className="flex size-10 shrink-0 items-center justify-center rounded-lg bg-muted/50">
              <card.icon className="size-[18px] text-foreground" />
            </div>
            <div>
              <p className="text-[11px] text-muted-foreground">{card.label}</p>
              <p className="text-xl font-bold tabular-nums leading-tight">
                {card.value}
                {card.unit && (
                  <span className="ml-0.5 text-xs font-normal text-muted-foreground">
                    {card.unit}
                  </span>
                )}
              </p>
            </div>
          </div>
        ))}
      </div>

      {/* ===== Calendar + Heatmap + Insights ===== */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-12">
        {/* Calendar */}
        <Card className="lg:col-span-3">
          <CardContent className="p-4">
            <div className="mb-3 flex items-center justify-between">
              <h2 className="flex items-center gap-2 text-sm font-medium">
                <CalendarDays className="size-4 text-foreground" />
                {format(currentMonth, "M月", { locale: zhCN })}
              </h2>
              <div className="flex gap-0.5">
                <button
                  onClick={prevMonth}
                  className="rounded-md p-1 transition-colors hover:bg-accent"
                >
                  <ChevronLeft className="size-4" />
                </button>
                <button
                  onClick={nextMonth}
                  disabled={isCurrentMonth}
                  className="rounded-md p-1 transition-colors hover:bg-accent disabled:opacity-30"
                >
                  <ChevronRight className="size-4" />
                </button>
              </div>
            </div>

            <div className="mb-1 grid grid-cols-7 text-center text-[10px] font-medium text-muted-foreground/50">
              {["一", "二", "三", "四", "五", "六", "日"].map((d) => (
                <div key={d}>{d}</div>
              ))}
            </div>

            <div className="grid grid-cols-7 gap-px">
              {calendarDays.map((day, i) => {
                const dateKey = format(day, "yyyy-MM-dd");
                const count = bookmarksPerDay.get(dateKey) ?? 0;
                const isToday = isSameDay(day, new Date());
                const inMonth = isSameMonth(day, currentMonth);
                const intensity =
                  count === 0
                    ? ""
                    : count <= 2
                      ? "bg-emerald-200/60 dark:bg-emerald-900/40"
                      : count <= 5
                        ? "bg-emerald-400/70 dark:bg-emerald-700/50"
                        : count <= 10
                          ? "bg-emerald-500 text-white"
                          : "bg-emerald-700 text-white";

                return (
                  <div
                    key={i}
                    className={cn(
                      "flex aspect-square items-center justify-center rounded text-[11px]",
                      !inMonth && "text-muted-foreground/20",
                      inMonth && !intensity && "hover:bg-accent/50",
                      intensity,
                      isToday && "ring-1.5 ring-foreground",
                    )}
                  >
                    {format(day, "d")}
                  </div>
                );
              })}
            </div>

            <div className="mt-3 flex items-center justify-between text-[10px] text-muted-foreground/60">
              <span>当月 {stats?.currentMonthCount ?? 0} 条</span>
              <div className="flex items-center gap-1">
                <span>少</span>
                <div className="size-2 rounded-sm bg-muted/30" />
                <div className="size-2 rounded-sm bg-emerald-200/60" />
                <div className="size-2 rounded-sm bg-emerald-400/70" />
                <div className="size-2 rounded-sm bg-emerald-500" />
                <span>多</span>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Heatmap */}
        <Card className="lg:col-span-5">
          <CardContent className="p-5">
            <div className="mb-3 flex items-center justify-between">
              <h2 className="flex items-center gap-2 text-sm font-medium">
                <div className="size-1.5 rounded-full bg-foreground" />
                采集热力图
              </h2>
            </div>
            <Heatmap data={stats?.heatmapData ?? []} />
          </CardContent>
        </Card>

        {/* Insights */}
        <div className="flex flex-col gap-4 lg:col-span-4">
          <Card>
            <CardContent className="p-4">
              <h3 className="mb-3 flex items-center gap-2 text-sm font-medium">
                <TrendingUp className="size-4 text-foreground" />
                内容分布
              </h3>
              <div className="space-y-2.5">
                {[
                  {
                    type: "link" as const,
                    label: "链接",
                    icon: Link2,
                    color: "bg-blue-500",
                    textColor: "text-foreground",
                    bgColor: "bg-muted",
                  },
                  {
                    type: "text" as const,
                    label: "笔记",
                    icon: Bookmark,
                    color: "bg-emerald-500",
                    textColor: "text-foreground",
                    bgColor: "bg-muted",
                  },
                  {
                    type: "asset" as const,
                    label: "资产",
                    icon: ArrowDownToLine,
                    color: "bg-amber-500",
                    textColor: "text-foreground",
                    bgColor: "bg-muted",
                  },
                ].map((item) => {
                  const count = typeDistribution[item.type];
                  const total = stats?.totalCount ?? 0;
                  const pct = total > 0 ? Math.round((count / total) * 100) : 0;
                  return (
                    <div key={item.type} className="flex items-center gap-3">
                      <div
                        className={`flex size-7 items-center justify-center rounded-md ${item.bgColor}`}
                      >
                        <item.icon className={`size-3.5 ${item.textColor}`} />
                      </div>
                      <div className="flex-1">
                        <div className="flex items-center justify-between text-xs">
                          <span className="font-medium">{item.label}</span>
                          <span className="text-muted-foreground">
                            {count} ({pct}%)
                          </span>
                        </div>
                        <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-secondary">
                          <div
                            className={`h-full rounded-full ${item.color}`}
                            style={{ width: `${pct}%` }}
                          />
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </CardContent>
          </Card>

          {topDomains.length > 0 && (
            <Card>
              <CardContent className="p-4">
                <h3 className="mb-3 flex items-center gap-2 text-sm font-medium">
                  <Link2 className="size-4 text-foreground" />
                  热门域名
                </h3>
                <div className="space-y-2">
                  {topDomains.map(({ domain, count }, i) => (
                    <div
                      key={domain}
                      className="flex items-center gap-2.5 text-xs"
                    >
                      <span className="flex size-5 items-center justify-center rounded bg-secondary text-[10px] font-medium text-muted-foreground">
                        {i + 1}
                      </span>
                      <span className="flex-1 truncate font-medium">
                        {domain}
                      </span>
                      <span className="text-muted-foreground">{count}</span>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      </div>

      {/* ===== All Bookmarks - sorted by time desc ===== */}
      <div className="flex flex-col gap-4">
        <div className="flex items-center justify-between">
          <h2 className="flex items-center gap-2 text-base font-semibold">
            <Timer className="size-4 text-foreground/70" />
            全部采集
            <span className="rounded-full bg-muted px-2 py-0.5 text-xs text-muted-foreground">
              {allBookmarks.length}
            </span>
          </h2>
        </div>

        {allBookmarks.length === 0 ? (
          <div className="flex flex-col items-center justify-center rounded-xl border border-dashed bg-muted/20 py-16 text-center">
            <div className="mb-3 flex size-12 items-center justify-center rounded-full bg-muted">
              <Library className="size-6 text-muted-foreground" />
            </div>
            <p className="text-sm font-medium text-muted-foreground">
              暂无采集记录
            </p>
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {allBookmarks.map((bookmark) => (
              <BookmarkListItem key={bookmark.id} bookmark={bookmark} />
            ))}
          </div>
        )}

        {hasNextPage && (
          <div className="flex justify-center pt-2">
            <button
              onClick={() => fetchNextPage()}
              disabled={isFetchingNextPage}
              className="flex items-center gap-2 rounded-lg border bg-card px-5 py-2.5 text-sm font-medium text-muted-foreground transition-all hover:bg-accent hover:text-foreground active:scale-[0.98] disabled:opacity-50"
            >
              {isFetchingNextPage ? (
                <div className="size-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
              ) : (
                <ChevronDown className="size-4" />
              )}
              加载更多
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

function ChevronDown({ className }: { className?: string }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
    >
      <path d="m6 9 6 6 6-6" />
    </svg>
  );
}
