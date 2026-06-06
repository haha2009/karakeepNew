import type { ZGitHubProject } from "@karakeep/shared/types/bookmarks";

function formatStars(count: number | null): string {
  if (count === null || count === undefined) return "";
  if (count >= 1000) return `${(count / 1000).toFixed(1)}k`;
  return String(count);
}

const LANG_COLORS: Record<string, string> = {
  TypeScript: "bg-blue-500",
  JavaScript: "bg-yellow-400",
  Rust: "bg-orange-600",
  Python: "bg-blue-600",
  Go: "bg-cyan-500",
  Java: "bg-red-500",
  Ruby: "bg-red-600",
  C: "bg-gray-500",
  "C++": "bg-purple-600",
  Shell: "bg-green-600",
  HTML: "bg-orange-500",
  CSS: "bg-purple-400",
  Kotlin: "bg-purple-500",
  Swift: "bg-orange-500",
  Dart: "bg-blue-400",
  Zig: "bg-yellow-600",
};

export default function GitHubProjectBadge({
  project,
}: {
  project: ZGitHubProject;
}) {
  return (
    <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
      {typeof project.stars === "number" && (
        <span className="inline-flex items-center gap-0.5" title="Stars">
          <svg className="size-3" viewBox="0 0 16 16" fill="currentColor">
            <path d="M8 .25a.75.75 0 01.673.418l1.882 3.815 4.21.612a.75.75 0 01.416 1.279l-3.046 2.97.719 4.192a.75.75 0 01-1.088.791L8 12.347l-3.766 1.98a.75.75 0 01-1.088-.79l.72-4.192L.82 6.374a.75.75 0 01.416-1.28l4.21-.611L7.327.668A.75.75 0 018 .25z" />
          </svg>
          {formatStars(project.stars)}
        </span>
      )}
      {project.language && (
        <span className="inline-flex items-center gap-1">
          <span
            className={`inline-block size-2 rounded-full ${LANG_COLORS[project.language] ?? "bg-gray-400"}`}
          />
          {project.language}
        </span>
      )}
      {project.license && (
        <span className="inline-flex items-center gap-0.5">
          {project.license}
        </span>
      )}
      {project.topics && project.topics.length > 0 && (
        <span className="inline-flex flex-wrap gap-1">
          {project.topics.slice(0, 3).map((topic) => (
            <span
              key={topic}
              className="rounded bg-muted px-1.5 py-0.5 text-[10px] text-muted-foreground"
            >
              {topic}
            </span>
          ))}
          {project.topics.length > 3 && (
            <span className="text-[10px] text-muted-foreground">
              +{project.topics.length - 3}
            </span>
          )}
        </span>
      )}
    </div>
  );
}

export { formatStars };
