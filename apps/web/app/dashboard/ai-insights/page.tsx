"use client";

import React from "react";
import { useQuery } from "@tanstack/react-query";
import { Brain, ExternalLink, Loader2, Star, Tag } from "lucide-react";
import { useTRPC } from "@karakeep/shared-react/trpc";
import type { ZGitHubProjectFull } from "@karakeep/shared/types/bookmarks";

export default function AiInsightsPage() {
  const api = useTRPC();

  const projectsQuery = useQuery(
    api.github.search.queryOptions({
      limit: 50,
      sortOrder: "desc",
    }),
  );

  const unprocessedQuery = useQuery(api.github.getUnprocessed.queryOptions());

  const projects = projectsQuery.data?.projects ?? [];
  const stats = unprocessedQuery.data;

  const analyzed = projects.filter((p) => p.humanSummary || p.agentDossier);

  return (
    <div className="mx-auto max-w-5xl space-y-8 p-6">
      {/* Header */}
      <div className="flex items-center gap-3">
        <div className="flex size-10 items-center justify-center rounded-xl bg-purple-100 text-purple-600">
          <Brain className="size-5" />
        </div>
        <div>
          <h1 className="text-2xl font-bold">AI 理解</h1>
          <p className="text-sm text-muted-foreground">
            AI 自动分析你收藏的项目，生成摘要、标签和洞察
          </p>
        </div>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <StatCard label="总项目数" value={stats?.total ?? "–"} color="blue" />
        <StatCard
          label="已分析"
          value={stats?.completed ?? "–"}
          color="green"
        />
        <StatCard
          label="待处理"
          value={stats?.unprocessed ?? "–"}
          color="amber"
        />
        <StatCard label="失败" value={stats?.failed ?? "–"} color="red" />
      </div>

      {/* Projects List */}
      {projectsQuery.isLoading ? (
        <div className="flex items-center justify-center py-20">
          <Loader2 className="size-6 animate-spin text-muted-foreground" />
        </div>
      ) : analyzed.length === 0 ? (
        <div className="flex flex-col items-center justify-center gap-3 py-20 text-muted-foreground">
          <Brain className="size-10 opacity-40" />
          <p className="text-lg font-medium">暂无 AI 分析结果</p>
          <p className="text-sm">
            在采集页面添加 GitHub 项目链接，AI 将自动分析并生成摘要
          </p>
        </div>
      ) : (
        <div className="space-y-4">
          <h2 className="text-lg font-semibold">已分析项目</h2>
          <div className="grid gap-4 sm:grid-cols-2">
            {analyzed.map((project) => (
              <ProjectCard key={project.id} project={project} />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function StatCard({
  label,
  value,
  color,
}: {
  label: string;
  value: number | string;
  color: "blue" | "green" | "amber" | "red";
}) {
  const colorMap = {
    blue: "bg-blue-50 text-blue-700 border-blue-200",
    green: "bg-green-50 text-green-700 border-green-200",
    amber: "bg-amber-50 text-amber-700 border-amber-200",
    red: "bg-red-50 text-red-700 border-red-200",
  };

  return (
    <div className={`rounded-xl border p-4 ${colorMap[color]}`}>
      <p className="text-xs font-medium opacity-70">{label}</p>
      <p className="mt-1 text-2xl font-bold">{value}</p>
    </div>
  );
}

function ProjectCard({ project }: { project: ZGitHubProjectFull }) {
  return (
    <div className="group rounded-xl border bg-card p-4 transition-shadow hover:shadow-md">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0 flex-1">
          <a
            href={project.url}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1 text-sm font-semibold text-foreground hover:underline"
          >
            {project.fullName}
            <ExternalLink className="size-3 opacity-50" />
          </a>
          {project.description && (
            <p className="mt-1 line-clamp-2 text-xs text-muted-foreground">
              {project.description}
            </p>
          )}
        </div>
      </div>

      {/* AI Summary */}
      {project.humanSummary && (
        <div className="mt-3 rounded-lg bg-purple-50 p-3 dark:bg-purple-950/30">
          <p className="text-xs font-medium text-purple-700 dark:text-purple-300">
            AI 摘要
          </p>
          <p className="mt-1 text-sm text-purple-900 dark:text-purple-100">
            {project.humanSummary}
          </p>
        </div>
      )}

      {/* Tags */}
      {project.agentTags && project.agentTags.length > 0 && (
        <div className="mt-3 flex flex-wrap gap-1.5">
          {project.agentTags.map((tag: string) => (
            <span
              key={tag}
              className="inline-flex items-center gap-1 rounded-full bg-secondary px-2 py-0.5 text-[10px] font-medium text-secondary-foreground"
            >
              <Tag className="size-2.5" />
              {tag}
            </span>
          ))}
        </div>
      )}

      {/* Meta */}
      <div className="mt-3 flex items-center gap-3 text-xs text-muted-foreground">
        {project.stars != null && (
          <span className="flex items-center gap-1">
            <Star className="size-3" />
            {project.stars.toLocaleString()}
          </span>
        )}
        {project.language && <span>{project.language}</span>}
        {project.valueScore != null && (
          <span className="font-medium text-foreground">
            价值评分 {project.valueScore}/10
          </span>
        )}
      </div>
    </div>
  );
}
