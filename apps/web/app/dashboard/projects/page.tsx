"use client";

import React from "react";
import { useQuery } from "@tanstack/react-query";
import { Star, FolderOpen, Globe } from "lucide-react";
import { useTRPC } from "@karakeep/shared-react/trpc";

export default function ProjectsPage() {
  const api = useTRPC();

  const profileQuery = useQuery(api.github.profile.queryOptions());
  const searchQuery = useQuery(
    api.github.search.queryOptions({
      limit: 50,
      sortOrder: "desc",
    }),
  );

  const [selectedLang, setSelectedLang] = React.useState<string>("");
  const languages = profileQuery.data?.languages ?? [];

  const filteredQuery = useQuery(
    api.github.search.queryOptions({
      limit: 50,
      sortOrder: "desc",
      ...(selectedLang ? { language: selectedLang } : {}),
    }),
  );

  const displayQuery = selectedLang ? filteredQuery : searchQuery;
  const projects = displayQuery.data?.projects ?? [];
  const profile = profileQuery.data;

  return (
    <div className="mx-auto max-w-5xl space-y-6 p-6">
      {/* Header */}
      <div className="flex items-center gap-3">
        <div className="flex size-10 items-center justify-center rounded-xl bg-blue-100 text-blue-600">
          <FolderOpen className="size-5" />
        </div>
        <div>
          <h1 className="text-2xl font-bold">GitHub 项目</h1>
          <p className="text-sm text-muted-foreground">
            从你收藏的书签中自动识别和提取的 GitHub 开源项目
          </p>
        </div>
      </div>

      {/* Stats */}
      {profileQuery.isLoading ? (
        <div className="flex items-center justify-center py-8">
          <div className="size-6 animate-spin rounded-full border-2 border-muted-foreground/30 border-t-foreground" />
        </div>
      ) : profile ? (
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <StatCard label="项目数" value={profile.totalProjects} color="blue" />
          <StatCard label="总 Stars" value={profile.totalStars.toLocaleString()} color="amber" />
          <StatCard label="平均 Stars" value={profile.avgStars.toLocaleString()} color="purple" />
          <StatCard label="语言种类" value={profile.languages.length} color="green" />
        </div>
      ) : null}

      {/* Language Filter */}
      {languages.length > 0 && (
        <div className="flex items-center gap-3">
          <label className="text-sm text-muted-foreground">语言筛选：</label>
          <select
            value={selectedLang}
            onChange={(e) => setSelectedLang(e.target.value)}
            className="rounded-md border bg-background px-3 py-1.5 text-sm"
          >
            <option value="">全部</option>
            {languages.map((l) => (
              <option key={l.language} value={l.language}>
                {l.language} ({l.count})
              </option>
            ))}
          </select>
        </div>
      )}

      {/* Projects Grid */}
      {displayQuery.isLoading ? (
        <div className="flex items-center justify-center py-20">
          <div className="size-6 animate-spin rounded-full border-2 border-muted-foreground/30 border-t-foreground" />
        </div>
      ) : projects.length === 0 ? (
        <div className="flex flex-col items-center justify-center gap-3 py-20 text-muted-foreground">
          <Globe className="size-10 opacity-40" />
          <p className="text-lg font-medium">暂无项目</p>
          <p className="text-sm">收藏 GitHub 链接后，项目将自动出现在这里</p>
        </div>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2">
          {projects.map((project) => (
            <ProjectCard key={project.id} project={project} />
          ))}
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
  color: "blue" | "amber" | "purple" | "green";
}) {
  const colorMap = {
    blue: "bg-blue-50 text-blue-700 border-blue-200 dark:bg-blue-950/40 dark:text-blue-300 dark:border-blue-800",
    amber: "bg-amber-50 text-amber-700 border-amber-200 dark:bg-amber-950/40 dark:text-amber-300 dark:border-amber-800",
    purple: "bg-purple-50 text-purple-700 border-purple-200 dark:bg-purple-950/40 dark:text-purple-300 dark:border-purple-800",
    green: "bg-green-50 text-green-700 border-green-200 dark:bg-green-950/40 dark:text-green-300 dark:border-green-800",
  };

  return (
    <div className={`rounded-xl border p-4 font-mono ${colorMap[color]}`}>
      <p className="text-xs font-medium opacity-70">{label}</p>
      <p className="mt-1 text-2xl font-bold">{value}</p>
    </div>
  );
}

function ProjectCard({ project }: { project: { id: string; fullName: string; url: string; description: string | null; humanSummary: string | null; stars: number | null; language: string | null; tags: string[] | null; valueScore: string | null; agentDossier: unknown } }) {
  const summary = project.humanSummary ?? project.description;

  return (
    <div className="group rounded-xl border bg-card p-4 transition-shadow hover:shadow-md">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0 flex-1">
          <a
            href={project.url}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1.5 text-sm font-semibold hover:underline"
          >
            {project.fullName}
            <Globe className="size-3 opacity-50" />
          </a>
          {summary && (
            <p className="mt-1 line-clamp-2 text-xs text-muted-foreground">
              {summary}
            </p>
          )}
        </div>
      </div>

      {/* Tags */}
      {project.tags && project.tags.length > 0 && (
        <div className="mt-3 flex flex-wrap gap-1.5">
          {project.tags.slice(0, 6).map((tag: string) => (
            <span
              key={tag}
              className="rounded-full bg-secondary px-2 py-0.5 text-[10px] font-medium text-secondary-foreground"
            >
              #{tag}
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
        {project.language && <span className="rounded bg-muted px-1.5 py-0.5">{project.language}</span>}
        {project.valueScore && project.valueScore !== "unscored" && (
          <span className="font-medium text-foreground">⭐ {project.valueScore}</span>
        )}
      </div>
    </div>
  );
}
