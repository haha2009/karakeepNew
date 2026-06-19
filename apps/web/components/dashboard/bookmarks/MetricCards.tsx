"use client";

import React from "react";
import { Card, CardContent } from "@/components/ui/card";
import { useTranslation } from "@/lib/i18n/client";

interface MetricCardsProps {
  todayCount: number;
  totalCount: number;
  usageDays: number;
}

export default function MetricCards({
  todayCount,
  totalCount,
  usageDays,
}: MetricCardsProps) {
  const { t } = useTranslation();

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
      <Card>
        <CardContent className="flex flex-col items-center justify-center p-6">
          <span className="text-3xl font-bold">{todayCount}</span>
          <span className="mt-1 text-sm text-muted-foreground">
            {t("stats.today_count")}
          </span>
        </CardContent>
      </Card>
      <Card>
        <CardContent className="flex flex-col items-center justify-center p-6">
          <span className="text-3xl font-bold">{totalCount}</span>
          <span className="mt-1 text-sm text-muted-foreground">
            {t("stats.total_count")}
          </span>
        </CardContent>
      </Card>
      <Card>
        <CardContent className="flex flex-col items-center justify-center p-6">
          <span className="text-3xl font-bold">
            {usageDays}
            <span className="text-base font-normal">{t("stats.days")}</span>
          </span>
          <span className="mt-1 text-sm text-muted-foreground">
            {t("stats.usage_days")}
          </span>
        </CardContent>
      </Card>
    </div>
  );
}
