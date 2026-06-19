"use client";

import React, { useMemo, useState } from "react";
import { isSameMonth } from "date-fns";
import { FullPageSpinner } from "@/components/ui/full-page-spinner";
import { Card, CardContent } from "@/components/ui/card";
import { ActionButton } from "@/components/ui/action-button";
import { Database } from "lucide-react";
import { useTRPC } from "@karakeep/shared-react/trpc";
import { useTranslation } from "@/lib/i18n/client";
import { useInfiniteQuery, useQuery } from "@tanstack/react-query";

import MetricCards from "./MetricCards";
import Heatmap from "./Heatmap";
import MonthNavigator from "./MonthNavigator";
import BookmarkListItem from "./BookmarkListItem";
import AddDropdownMenu from "./AddDropdownMenu";

const PAGE_TITLE_KEY = "bookmarks.title";
const NO_BOOKMARKS_KEY = "bookmarks.no_bookmarks_in_month";

export default function BookmarkStatsPage() {
  const api = useTRPC();
  const { t } = useTranslation();
  const [currentMonth, setCurrentMonth] = useState(new Date());

  // Fetch stats
  const { data: stats, isLoading: statsLoading } = useQuery(
    api.bookmarks.getStats.queryOptions(),
  );

  // Fetch bookmarks
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

  // Filter bookmarks to current month
  const allBookmarks = useMemo(
    () => data?.pages.flatMap((p) => p.bookmarks) ?? [],
    [data],
  );

  const filteredBookmarks = useMemo(
    () => allBookmarks.filter((b) => isSameMonth(b.createdAt, currentMonth)),
    [allBookmarks, currentMonth],
  );

  if (statsLoading || bookmarksLoading) {
    return <FullPageSpinner />;
  }

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-6 p-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Database className="size-5 text-muted-foreground" />
          <h1 className="text-xl font-semibold">{t(PAGE_TITLE_KEY)}</h1>
        </div>
        <AddDropdownMenu />
      </div>

      {/* Metric Cards */}
      <MetricCards
        todayCount={stats?.todayCount ?? 0}
        totalCount={stats?.totalCount ?? 0}
        usageDays={stats?.usageDays ?? 0}
      />

      {/* Heatmap */}
      <Card>
        <CardContent className="p-4">
          <h2 className="mb-3 text-sm font-medium text-muted-foreground">
            {t("stats.heatmap_title")}
          </h2>
          <Heatmap data={stats?.heatmapData ?? []} />
        </CardContent>
      </Card>

      {/* Month Navigator */}
      <MonthNavigator
        currentMonth={currentMonth}
        onMonthChange={setCurrentMonth}
      />

      {/* Bookmark List */}
      <div className="flex flex-col gap-3">
        {filteredBookmarks.length === 0 ? (
          <div className="py-12 text-center text-sm text-muted-foreground">
            {t(NO_BOOKMARKS_KEY)}
          </div>
        ) : (
          filteredBookmarks.map((bookmark) => (
            <BookmarkListItem key={bookmark.id} bookmark={bookmark} />
          ))
        )}
        {hasNextPage && (
          <ActionButton
            variant="ghost"
            onClick={() => fetchNextPage()}
            loading={isFetchingNextPage}
          >
            {t("actions.load_more")}
          </ActionButton>
        )}
      </div>
    </div>
  );
}
