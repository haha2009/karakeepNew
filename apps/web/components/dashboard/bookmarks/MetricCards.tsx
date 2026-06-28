"use client";

import React from "react";
import { useTranslation } from "@/lib/i18n/client";
import { Flame, Hash, Library, TrendingUp } from "lucide-react";

interface MetricCardsProps {
  todayCount: number;
  totalCount: number;
  usageDays: number;
  tagCount?: number;
}

const MetricCards = ({
  todayCount,
  totalCount,
  usageDays,
  tagCount = 0,
}: MetricCardsProps) => {
  const { t } = useTranslation();

  const cards = [
    {
      label: t("stats.today_count"),
      value: todayCount,
      icon: TrendingUp,
      color: "text-emerald-600",
      bg: "bg-emerald-500/10",
      ring: "ring-emerald-500/20",
    },
    {
      label: t("stats.total_count"),
      value: totalCount,
      icon: Library,
      color: "text-blue-600",
      bg: "bg-blue-500/10",
      ring: "ring-blue-500/20",
    },
    {
      label: t("stats.usage_days"),
      value: usageDays,
      unit: t("stats.days"),
      icon: Flame,
      color: "text-orange-600",
      bg: "bg-orange-500/10",
      ring: "ring-orange-500/20",
    },
    {
      label: "标签数",
      value: tagCount,
      icon: Hash,
      color: "text-purple-600",
      bg: "bg-purple-500/10",
      ring: "ring-purple-500/20",
    },
  ];

  return (
    <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
      {cards.map((card) => (
        <div
          key={card.label}
          className="flex items-center gap-3 rounded-xl border bg-background/80 p-3.5 backdrop-blur-sm transition-all hover:shadow-sm"
        >
          <div
            className={`flex size-10 shrink-0 items-center justify-center rounded-lg ${card.bg}`}
          >
            <card.icon className={`size-5 ${card.color}`} />
          </div>
          <div className="min-w-0">
            <p className="text-[11px] font-medium text-muted-foreground">
              {card.label}
            </p>
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
  );
};

export default MetricCards;
