"use client";

import React, { useMemo } from "react";
import type { ZHeatmapDay } from "@karakeep/shared/types/bookmarks";

interface HeatmapProps {
  data: ZHeatmapDay[];
}

function getColor(count: number): string {
  if (count === 0) return "bg-muted";
  if (count === 1) return "bg-[var(--heatmap-1)]";
  if (count <= 3) return "bg-[var(--heatmap-2)]";
  if (count <= 5) return "bg-[var(--heatmap-3)]";
  return "bg-[var(--heatmap-4)]";
}

function getTooltip(count: number, date: string): string {
  return `${date}: ${count} item${count !== 1 ? "s" : ""}`;
}

export default function Heatmap({ data }: HeatmapProps) {
  const { weeks, months } = useMemo(() => {
    const countMap = new Map<string, number>();
    for (const d of data) {
      countMap.set(d.date, d.count);
    }

    // Generate last 26 weeks (≈6 months)
    const today = new Date();
    const currentDayOfWeek = today.getDay(); // 0=Sun, 1=Mon, ...
    const daysToMonday = (currentDayOfWeek + 6) % 7; // days since last Monday

    // Start from the Monday of 25 weeks ago
    const startDate = new Date(today);
    startDate.setDate(startDate.getDate() - daysToMonday - 25 * 7);
    startDate.setHours(0, 0, 0, 0);

    const weeksArr: { date: Date; count: number }[][] = [];
    const monthLabels: { label: string; col: number }[] = [];
    let lastMonth = -1;

    for (let week = 0; week < 26; week++) {
      const weekData: { date: Date; count: number }[] = [];
      for (let day = 0; day < 7; day++) {
        const cellDate = new Date(startDate);
        cellDate.setDate(startDate.getDate() + week * 7 + day);
        const dateStr = cellDate.toISOString().slice(0, 10);
        weekData.push({
          date: cellDate,
          count: countMap.get(dateStr) ?? 0,
        });
      }
      weeksArr.push(weekData);

      // Check if this week's Thursday falls in a new month (ISO week convention)
      const thursday = new Date(startDate);
      thursday.setDate(startDate.getDate() + week * 7 + 3);
      const month = thursday.getMonth();
      if (month !== lastMonth) {
        monthLabels.push({
          label: thursday.toLocaleDateString("zh-CN", { month: "short" }),
          col: week,
        });
        lastMonth = month;
      }
    }

    return { weeks: weeksArr, months: monthLabels };
  }, [data]);

  return (
    <div className="overflow-x-auto">
      {/* Month labels */}
      <div className="mb-1 flex" style={{ gap: "14px" }}>
        {months.map((m, i) => (
          <div
            key={i}
            className="text-[10px] text-muted-foreground"
            style={{ marginLeft: i === 0 ? m.col * 14 : 0 }}
          >
            {m.label}
          </div>
        ))}
      </div>

      {/* Grid: 7 rows (Mon-Sun) × 26 columns (weeks) */}
      <div className="flex gap-[2px]">
        {weeks.map((week, weekIdx) => (
          <div key={weekIdx} className="flex flex-col gap-[2px]">
            {week.map((cell, dayIdx) => (
              <div
                key={dayIdx}
                className={`h-[11px] w-[11px] rounded-sm ${getColor(cell.count)}`}
                title={getTooltip(
                  cell.count,
                  cell.date.toISOString().slice(0, 10),
                )}
              />
            ))}
          </div>
        ))}
      </div>

      {/* Legend */}
      <div className="mt-2 flex items-center gap-1 text-[10px] text-muted-foreground">
        <span>Less</span>
        <div className="h-[11px] w-[11px] rounded-sm bg-muted" />
        <div className="h-[11px] w-[11px] rounded-sm bg-[var(--heatmap-1)]" />
        <div className="h-[11px] w-[11px] rounded-sm bg-[var(--heatmap-2)]" />
        <div className="h-[11px] w-[11px] rounded-sm bg-[var(--heatmap-3)]" />
        <div className="h-[11px] w-[11px] rounded-sm bg-[var(--heatmap-4)]" />
        <span>More</span>
      </div>
    </div>
  );
}
