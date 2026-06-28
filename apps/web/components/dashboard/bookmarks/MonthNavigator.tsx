"use client";

import React from "react";
import {
  addMonths,
  format,
  isBefore,
  isSameMonth,
  startOfMonth,
} from "date-fns";
import { zhCN } from "date-fns/locale";
import { ChevronLeft, ChevronRight } from "lucide-react";

import { Button } from "@/components/ui/button";

interface MonthNavigatorProps {
  currentMonth: Date;
  onMonthChange: (month: Date) => void;
}

export default function MonthNavigator({
  currentMonth,
  onMonthChange,
}: MonthNavigatorProps) {
  const today = new Date();
  const currentMonthStart = startOfMonth(today);
  const prevMonth = addMonths(currentMonth, -1);
  const nextMonth = addMonths(currentMonth, 1);

  const canGoNext =
    isBefore(startOfMonth(nextMonth), currentMonthStart) ||
    isSameMonth(startOfMonth(nextMonth), currentMonthStart);
  const canGoPrev = true; // Allow navigating to any past month

  return (
    <div className="flex items-center justify-center gap-4">
      <Button
        variant="ghost"
        size="icon"
        className="transition-all duration-200 hover:scale-110 active:scale-95"
        onClick={() => onMonthChange(prevMonth)}
        disabled={!canGoPrev}
      >
        <ChevronLeft className="size-4" />
      </Button>
      <span className="min-w-[120px] text-center text-sm font-medium">
        {format(currentMonth, "yyyy年M月", { locale: zhCN })}
      </span>
      <Button
        variant="ghost"
        size="icon"
        className="transition-all duration-200 hover:scale-110 active:scale-95"
        onClick={() => onMonthChange(nextMonth)}
        disabled={!canGoNext}
      >
        <ChevronRight className="size-4" />
      </Button>
    </div>
  );
}
