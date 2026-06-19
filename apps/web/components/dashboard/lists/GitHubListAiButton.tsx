"use client";

import React from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  Sparkle,
  Loader2,
  CheckCircle2,
  AlertCircle,
  XCircle,
} from "lucide-react";
import { useTRPC } from "@karakeep/shared-react/trpc";

const POLL_INTERVAL_MS = 2000;
const RESET_DELAY_MS = 6000;

type Phase = "idle" | "processing" | "done" | "error";

export default function GitHubListAiButton() {
  const api = useTRPC();
  const queryClient = useQueryClient();

  // ── Local State (declared before queries that reference them) ──
  const [phase, setPhase] = React.useState<Phase>("idle");

  // ── Queries ──
  const unprocessedQuery = useQuery(
    api.github.getUnprocessed.queryOptions(undefined, {
      refetchInterval: (_data) => {
        // Only poll during processing
        return phase === "processing" ? POLL_INTERVAL_MS : false;
      },
    }),
  );

  const stats = unprocessedQuery.data;

  // ── Mutation ──
  const processAllMutation = useMutation(
    api.github.processAll.mutationOptions({
      onSuccess: (result) => {
        // Invalidate all related queries
        queryClient.invalidateQueries(api.github.getUnprocessed.pathFilter());
        queryClient.invalidateQueries(api.github.search.pathFilter());
        queryClient.invalidateQueries(api.bookmarks.getBookmarks.pathFilter());

        setFinalResult({
          total: result.total,
          enqueued: result.enqueued,
        });
        setPhase("done");
      },
      onError: (e) => {
        console.error("[GitHub AI] processAll failed:", e);
        setPhase("error");
        setFinalResult({ total: 0, enqueued: 0 });
      },
    }),
  );

  // ── Local State ──
  const [initialUnprocessed, setInitialUnprocessed] = React.useState(0);
  const [initialCompleted, setInitialCompleted] = React.useState(0);
  const [initialFailed, setInitialFailed] = React.useState(0);
  const [finalResult, setFinalResult] = React.useState({
    total: 0,
    enqueued: 0,
  });

  const timerRef = React.useRef<ReturnType<typeof setTimeout> | null>(null);

  // Cleanup timer on unmount
  React.useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, []);

  // ── Derived Progress ──
  const currentPending = stats?.pending ?? 0;
  const currentUnprocessed = stats?.unprocessed ?? 0;
  const currentCompleted = stats?.completed ?? 0;
  const currentFailed = stats?.failed ?? 0;

  // Progress calculations
  const progressTotal = initialUnprocessed || 1;
  const completedDelta = currentCompleted - initialCompleted;
  const failedDelta = currentFailed - initialFailed;
  const startedDelta = completedDelta + failedDelta;
  const remainingCount = currentUnprocessed + currentPending;
  const progressPct = Math.min(
    Math.round((startedDelta / progressTotal) * 100),
    100,
  );

  // ── Handlers ──
  const handleProcessAll = () => {
    const data = unprocessedQuery.data;
    if (!data || data.unprocessed === 0) return;

    setInitialUnprocessed(data.unprocessed);
    setInitialCompleted(data.completed);
    setInitialFailed(data.failed);
    setPhase("processing");
    setFinalResult({ total: 0, enqueued: 0 });

    processAllMutation.mutate();
  };

  const handleReset = () => {
    setPhase("idle");
    setFinalResult({ total: 0, enqueued: 0 });
  };

  // Auto-reset after done/error
  React.useEffect(() => {
    if (phase === "done" || phase === "error") {
      if (timerRef.current) clearTimeout(timerRef.current);
      timerRef.current = setTimeout(() => {
        handleReset();
      }, RESET_DELAY_MS);
    }
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, [phase]);

  return (
    <>
      {/* ========== Trigger Button ========== */}
      <button
        onClick={handleProcessAll}
        disabled={
          phase === "processing" ||
          phase === "done" ||
          (!phase && (!stats || stats.unprocessed === 0))
        }
        className={`relative inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-xs font-medium transition-all disabled:cursor-not-allowed ${
          phase === "idle"
            ? "border-blue-200 bg-blue-50 text-blue-700 hover:bg-blue-100 disabled:opacity-50"
            : phase === "processing"
              ? "border-amber-200 bg-amber-50 text-amber-700"
              : phase === "done"
                ? "border-green-200 bg-green-50 text-green-700"
                : "border-red-200 bg-red-50 text-red-700"
        }`}
      >
        {/* Icon */}
        {phase === "idle" && <Sparkle className="size-3.5" />}
        {phase === "processing" && (
          <Loader2 className="size-3.5 animate-spin" />
        )}
        {phase === "done" && <CheckCircle2 className="size-3.5" />}
        {phase === "error" && <AlertCircle className="size-3.5" />}

        {/* Label */}
        {phase === "idle" && "AI 批量分析"}
        {phase === "processing" && `分析中 ${startedDelta}/${progressTotal}`}
        {phase === "done" &&
          `已入队 ${finalResult.enqueued}/${finalResult.total}`}
        {phase === "error" && "分析失败"}

        {/* Badge — idle: show unprocessed count */}
        {phase === "idle" && unprocessedQuery.isLoading && (
          <Loader2 className="ml-0.5 size-3 animate-spin" />
        )}
        {phase === "idle" && !unprocessedQuery.isLoading && stats && (
          <>
            {stats.unprocessed > 0 ? (
              <span className="ml-0.5 rounded-full bg-blue-600 px-1.5 py-0.5 text-[10px] font-bold text-white">
                {stats.unprocessed}
              </span>
            ) : (
              <CheckCircle2 className="ml-0.5 size-3.5 text-green-500" />
            )}
          </>
        )}

        {/* Processing badge: remaining in parenthetical */}
        {phase === "processing" && remainingCount > 0 && (
          <span className="ml-0.5 text-[10px] text-amber-500">
            ({remainingCount})
          </span>
        )}
      </button>

      {/* ========== Bottom Status Bar ========== */}
      {(phase === "processing" || phase === "done" || phase === "error") && (
        <div className="animate-slide-up fixed bottom-0 left-0 right-0 z-50">
          <div
            className={`mx-auto max-w-4xl border-t px-6 py-3 shadow-lg backdrop-blur-md ${
              phase === "processing"
                ? "border-amber-200 bg-amber-50/95"
                : phase === "done"
                  ? "border-green-200 bg-green-50/95"
                  : "border-red-200 bg-red-50/95"
            }`}
          >
            <div className="flex items-center justify-between">
              {/* Left: status + counts */}
              <div className="flex items-center gap-4">
                {/* Phase icon */}
                <span
                  className={`flex size-8 items-center justify-center rounded-full ${
                    phase === "processing"
                      ? "bg-amber-100 text-amber-600"
                      : phase === "done"
                        ? "bg-green-100 text-green-600"
                        : "bg-red-100 text-red-600"
                  }`}
                >
                  {phase === "processing" && (
                    <Loader2 className="size-4 animate-spin" />
                  )}
                  {phase === "done" && <CheckCircle2 className="size-4" />}
                  {phase === "error" && <XCircle className="size-4" />}
                </span>

                {/* Stats */}
                <div className="flex flex-col">
                  <span
                    className={`text-xs font-semibold ${
                      phase === "processing"
                        ? "text-amber-800"
                        : phase === "done"
                          ? "text-green-800"
                          : "text-red-800"
                    }`}
                  >
                    {phase === "processing" && "AI 批量分析中"}
                    {phase === "done" && "AI 分析完成"}
                    {phase === "error" && "AI 分析出错"}
                  </span>
                  <div className="mt-0.5 flex items-center gap-3 text-[11px] text-muted-foreground">
                    <span className="font-medium text-foreground">
                      总数{" "}
                      {phase === "done" ? finalResult.total : progressTotal}
                    </span>
                    <span className="flex items-center gap-1 text-green-600">
                      <CheckCircle2 className="size-3" />
                      {phase === "done" ? finalResult.enqueued : completedDelta}
                    </span>
                    {(phase === "done" ? failedDelta : failedDelta) > 0 && (
                      <span className="flex items-center gap-1 text-red-500">
                        <XCircle className="size-3" />
                        {phase === "done" ? failedDelta : failedDelta}
                      </span>
                    )}
                    {phase === "processing" && remainingCount > 0 && (
                      <span className="flex items-center gap-1 text-amber-500">
                        <Loader2 className="size-3 animate-spin" />
                        排队 ({remainingCount})
                      </span>
                    )}
                  </div>
                </div>
              </div>

              {/* Right: progress bar */}
              {phase === "processing" && (
                <div className="flex items-center gap-3">
                  <div className="h-2 w-32 overflow-hidden rounded-full bg-amber-200">
                    <div
                      className="h-full rounded-full bg-amber-500 transition-all duration-700 ease-out"
                      style={{ width: `${progressPct}%` }}
                    />
                  </div>
                  <span className="w-10 text-right text-[11px] font-medium text-amber-700">
                    {progressPct}%
                  </span>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </>
  );
}
