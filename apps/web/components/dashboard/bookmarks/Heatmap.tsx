"use client";

import React, { useState, useMemo } from "react";
import {
  addDays,
  addMonths,
  format,
  isSameDay,
  startOfMonth,
  startOfWeek,
} from "date-fns";
import { zhCN } from "date-fns/locale";

interface HeatmapDay {
  date: string;
  count: number;
}

interface HeatmapProps {
  data: HeatmapDay[];
}

const MONTHS_SHOWN = 6;
const DAY_LABELS = ["", "一", "", "三", "", "五", ""];
const MONTH_LABELS = [
  "1月",
  "2月",
  "3月",
  "4月",
  "5月",
  "6月",
  "7月",
  "8月",
  "9月",
  "10月",
  "11月",
  "12月",
];

function getColor(count: number): string {
  if (count === 0) return "bg-muted/30";
  if (count <= 2) return "bg-emerald-200 dark:bg-emerald-900/40";
  if (count <= 5) return "bg-emerald-400 dark:bg-emerald-700/60";
  if (count <= 10) return "bg-emerald-500 dark:bg-emerald-600";
  return "bg-emerald-700 dark:bg-emerald-500";
}

function getTextColor(count: number): string {
  if (count <= 2) return "text-foreground";
  return "text-white";
}

export default function Heatmap({ data }: HeatmapProps) {
  const [hoveredDay, setHoveredDay] = useState<HeatmapDay | null>(null);
  const [mousePos, setMousePos] = useState({ x: 0, y: 0 });

  const today = new Date();
  const startMonth = addMonths(today, -(MONTHS_SHOWN - 1));
  const gridStart = startOfWeek(startOfMonth(startMonth), { weekStartsOn: 1 });
  const gridEnd = today;
  const totalDays =
    Math.round((gridEnd.getTime() - gridStart.getTime()) / 86400000) + 1;
  const WEEKS = Math.ceil(totalDays / 7);

  const dataMap = useMemo(() => {
    const map = new Map<string, number>();
    for (const d of data) map.set(d.date, d.count);
    return map;
  }, [data]);

  const weeks = useMemo(() => {
    const result: (HeatmapDay | null)[][] = [];
    for (let w = 0; w < WEEKS; w++) {
      const week: (HeatmapDay | null)[] = [];
      for (let d = 0; d < 7; d++) {
        const date = addDays(gridStart, w * 7 + d);
        if (date > gridEnd) {
          week.push(null);
        } else {
          const dateStr = format(date, "yyyy-MM-dd");
          week.push({ date: dateStr, count: dataMap.get(dateStr) ?? 0 });
        }
      }
      result.push(week);
    }
    return result;
  }, [dataMap, gridStart, gridEnd, WEEKS]);

  const monthLabels = useMemo(() => {
    const labels: { label: string; offset: number }[] = [];
    let lastMonth = -1;
    let lastOffset = -99;
    const MIN_GAP = 2; // minimum columns between month labels

    for (let w = 0; w < weeks.length; w++) {
      // Find the dominant month in this column (most days belong to it)
      const monthCounts = new Map<number, number>();
      let total = 0;
      for (let d = 0; d < 7; d++) {
        const day = weeks[w][d];
        if (day) {
          const m = new Date(day.date).getMonth();
          monthCounts.set(m, (monthCounts.get(m) ?? 0) + 1);
          total++;
        }
      }
      if (total === 0) continue;

      let dominantMonth = -1;
      let maxCount = 0;
      for (const [m, c] of monthCounts) {
        if (c > maxCount) {
          maxCount = c;
          dominantMonth = m;
        }
      }

      // Only label if dominant month occupies >= half the visible days
      // and is different from last labeled month, with enough gap
      if (
        dominantMonth !== lastMonth &&
        maxCount >= Math.ceil(total / 2) &&
        w - lastOffset >= MIN_GAP
      ) {
        labels.push({ label: MONTH_LABELS[dominantMonth], offset: w });
        lastMonth = dominantMonth;
        lastOffset = w;
      }
    }
    return labels;
  }, [weeks]);

  const totalCount = useMemo(
    () => data.reduce((s, d) => s + d.count, 0),
    [data],
  );
  const activeDays = useMemo(
    () => data.filter((d) => d.count > 0).length,
    [data],
  );
  const maxDay = useMemo(() => {
    let max = 0;
    let maxDate = "";
    for (const d of data) {
      if (d.count > max) {
        max = d.count;
        maxDate = d.date;
      }
    }
    return { count: max, date: maxDate };
  }, [data]);

  const handleMouseMove = (e: React.MouseEvent, day: HeatmapDay) => {
    setHoveredDay(day);
    const rect = (e.currentTarget as HTMLElement).closest?.("[data-heatmap]");
    if (rect) {
      const cr = rect.getBoundingClientRect();
      setMousePos({ x: e.clientX - cr.left, y: e.clientY - cr.top });
    }
  };

  return (
    <div data-heatmap className="relative">
      {/* Stats row */}
      <div className="mb-4 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-1.5">
            <div className="size-2 rounded-full bg-foreground" />
            <span className="text-[11px] text-muted-foreground">
              总计{" "}
              <span className="font-semibold text-foreground">
                {totalCount}
              </span>
            </span>
          </div>
          <div className="flex items-center gap-1.5">
            <div className="size-2 rounded-full bg-foreground/40" />
            <span className="text-[11px] text-muted-foreground">
              活跃{" "}
              <span className="font-semibold text-foreground">
                {activeDays}
              </span>{" "}
              天
            </span>
          </div>
          {maxDay.count > 0 && (
            <div className="flex items-center gap-1.5">
              <div className="size-2 rounded-full bg-foreground/70" />
              <span className="text-[11px] text-muted-foreground">
                峰值{" "}
                <span className="font-semibold text-foreground">
                  {maxDay.count}
                </span>
                <span className="ml-0.5 text-muted-foreground/60">
                  {format(new Date(maxDay.date), "M/d", { locale: zhCN })}
                </span>
              </span>
            </div>
          )}
        </div>
        <span className="text-[10px] text-muted-foreground/60">
          近 {MONTHS_SHOWN} 个月
        </span>
      </div>

      {/* Month labels */}
      <div className="relative mb-1.5 ml-9 h-4">
        {monthLabels.map((m, i) => (
          <span
            key={i}
            className="absolute text-[10px] font-medium text-foreground/60"
            style={{ left: `${(m.offset / WEEKS) * 100}%` }}
          >
            {m.label}
          </span>
        ))}
      </div>

      {/* Grid */}
      <div className="flex">
        {/* Day labels */}
        <div className="flex flex-col gap-[3px] pr-2.5 pt-0">
          {DAY_LABELS.map((label, i) => (
            <div
              key={i}
              className="flex h-[15px] items-center justify-end text-[10px] text-muted-foreground/50"
              style={{ width: "22px" }}
            >
              {label}
            </div>
          ))}
        </div>

        {/* Cells */}
        <div className="flex flex-1 gap-[3px]">
          {weeks.map((week, wi) => (
            <div key={wi} className="flex flex-col gap-[3px]">
              {week.map((day, di) => (
                <div
                  key={di}
                  className={`h-[15px] w-[15px] rounded-[3px] transition-all duration-100 ${day ? getColor(day.count) + " " + getTextColor(day.count) : "bg-transparent"} ${day ? "cursor-pointer hover:scale-110 hover:shadow-sm" : ""} ${day && isSameDay(new Date(day.date), today) ? "ring-1.5 ring-foreground ring-offset-1 ring-offset-card" : ""} `}
                  onMouseEnter={(e) => day && handleMouseMove(e, day)}
                  onMouseLeave={() => setHoveredDay(null)}
                />
              ))}
            </div>
          ))}
        </div>
      </div>

      {/* Legend */}
      <div className="mt-4 flex items-center justify-between border-t border-border/50 pt-3">
        <div className="flex items-center gap-1.5 text-[10px] text-muted-foreground/60">
          <span>少</span>
          <div className="size-[12px] rounded-[3px] bg-muted/30" />
          <div className="size-[12px] rounded-[3px] bg-emerald-200 dark:bg-emerald-900/40" />
          <div className="size-[12px] rounded-[3px] bg-emerald-400 dark:bg-emerald-700/60" />
          <div className="size-[12px] rounded-[3px] bg-emerald-500 dark:bg-emerald-600" />
          <div className="size-[12px] rounded-[3px] bg-emerald-700 dark:bg-emerald-500" />
          <span>多</span>
        </div>
        <div className="flex items-center gap-1 text-[10px] text-muted-foreground/60">
          <div className="ring-1.5 size-[12px] rounded-[3px] bg-background ring-foreground/40" />
          <span>今日</span>
        </div>
      </div>

      {/* Tooltip */}
      {hoveredDay && (
        <div
          className="pointer-events-none absolute z-50 rounded-lg border border-border/80 bg-popover/95 px-3 py-2 text-xs shadow-xl backdrop-blur-sm"
          style={{ left: mousePos.x + 14, top: mousePos.y - 10 }}
        >
          <div className="font-medium text-foreground">
            {format(new Date(hoveredDay.date), "M月d日 EEEE", { locale: zhCN })}
          </div>
          <div className="mt-0.5 flex items-center gap-1.5 text-muted-foreground">
            <div className="size-1.5 rounded-full bg-foreground" />
            采集{" "}
            <span className="font-semibold text-foreground">
              {hoveredDay.count}
            </span>{" "}
            条
          </div>
        </div>
      )}
    </div>
  );
}
