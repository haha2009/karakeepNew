import { eq } from "drizzle-orm";
import { githubProjects, projectRecommendations } from "@karakeep/db/schema";
import { InferenceClientFactory } from "@karakeep/shared/inference";
import type { AgentDossier } from "@karakeep/shared/types/bookmarks";
import { TAXONOMY, classifyByRules } from "./github-tags";
import logger from "@karakeep/shared/logger";

const GITHUB_API_BASE = "https://api.github.com";

export interface GitHubRepoMetadata {
  fullName: string;
  url: string;
  name: string;
  owner: string;
  ownerAvatarUrl: string;
  description: string | null;
  stars: number;
  language: string | null;
  topics: string[];
  homepage: string | null;
  license: string | null;
  pushedAt: string | null;
}

/**
 * First path segment of github.com URLs that are NOT repositories
 * (e.g. github.com/orgs/foo, github.com/settings/profile, github.com/topics/react).
 * Used to reject non-repo URLs so we don't create junk bookmarks.
 */
const GITHUB_RESERVED_PATH_SEGMENTS = new Set([
  "orgs",
  "users",
  "settings",
  "topics",
  "search",
  "explore",
  "features",
  "pricing",
  "about",
  "trending",
  "notifications",
  "login",
  "signup",
  "join",
  "sessions",
  "security",
  "customer-stories",
  "marketplace",
  "collections",
  "events",
  "sponsors",
  "apps",
  "integrations",
  "enterprise",
  "team",
  "organizations",
  "new",
  "codespaces",
  "copilot",
  "gist",
  "watching",
  "stars",
]);

export function extractGitHubRepo(
  url: string,
): { owner: string; name: string; fullName: string } | null {
  try {
    const parsed = new URL(url);
    if (!parsed.hostname.replace(/^www\./, "").startsWith("github.com"))
      return null;
    const parts = parsed.pathname
      .replace(/^\/+/, "")
      .split("/")
      .filter(Boolean);
    if (parts.length < 2) return null;
    const [owner, name] = parts;
    if (!owner || !name) return null;
    // Reject reserved/non-repo paths (github.com/orgs/foo, github.com/settings/…)
    if (GITHUB_RESERVED_PATH_SEGMENTS.has(owner.toLowerCase())) return null;
    // Repo names shouldn't be a reserved segment either (defensive)
    if (GITHUB_RESERVED_PATH_SEGMENTS.has(name.toLowerCase())) return null;
    return { owner, name, fullName: `${owner}/${name}` };
  } catch {
    return null;
  }
}

export async function fetchGitHubRepoMetadata(
  owner: string,
  name: string,
): Promise<GitHubRepoMetadata | null> {
  const token = process.env.GITHUB_TOKEN;
  const headers: Record<string, string> = {
    Accept: "application/vnd.github.v3+json",
    "User-Agent": "karakeep",
  };
  if (token) headers.Authorization = `Bearer ${token}`;

  const response = await fetch(
    `${GITHUB_API_BASE}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(name)}`,
    { headers },
  );

  if (!response.ok) {
    if (response.status === 404) return null;
    if (response.status === 403) return null;
    throw new Error(`GitHub API error: ${response.status}`);
  }

  const data = await response.json();

  return {
    fullName: data.full_name,
    url: data.html_url,
    name: data.name,
    owner: data.owner.login,
    ownerAvatarUrl: data.owner.avatar_url,
    description: data.description,
    stars: data.stargazers_count,
    language: data.language,
    topics: data.topics ?? [],
    homepage: data.homepage,
    license: data.license?.spdx_id ?? null,
    pushedAt: data.pushed_at ?? null,
  };
}

const README_IMG_RE = /<img[^>]*src=(["'])([^"']+)\1[^>]*\/?\s*>/gi;

const SCREENSHOT_KEYWORDS =
  /screenshot|screenshots|demo|preview|showcase|展示|截图|预览/i;

function isBadge(url: string): boolean {
  try {
    const parsed = new URL(url);
    const hostname = parsed.hostname;
    let pathname = parsed.pathname;

    // Decode camo proxy URLs to check the original
    if (hostname === "camo.githubusercontent.com") {
      const parts = pathname.split("/");
      if (parts.length >= 3) {
        try {
          const hexStr = parts[2].replace(/[^0-9a-fA-F]/g, "");
          const decoded = Buffer.from(hexStr, "hex").toString("utf8");
          return isBadge(decoded);
        } catch {
          // ignore
        }
      }
      return true;
    }

    if (
      [
        "img.shields.io",
        "badge.fury.io",
        "travis-ci.org",
        "circleci.com",
        "codecov.io",
        "coveralls.io",
        "goreportcard.com",
        "gitter.im",
        "discordapp.com",
      ].some((d) => hostname.endsWith(d))
    )
      return true;
    if (pathname.includes("/badge.svg") || pathname.includes("/badges/"))
      return true;
    return false;
  } catch {
    return false;
  }
}

function isGitHubHosted(url: string): boolean {
  try {
    const hostname = new URL(url).hostname;
    return (
      hostname === "github.com" ||
      hostname.endsWith(".github.com") ||
      hostname.endsWith("githubusercontent.com") ||
      hostname === "camo.githubusercontent.com"
    );
  } catch {
    return false;
  }
}

const MD_IMG_RE = /!\[([^\]]*)\]\(([^)]+)\)/g;

function resolveReadmeUrl(url: string, owner: string, name: string): string {
  if (url.startsWith("http://") || url.startsWith("https://")) return url;
  const clean = url.startsWith("/") ? url.slice(1) : url;
  return `https://raw.githubusercontent.com/${encodeURIComponent(owner)}/${encodeURIComponent(name)}/main/${clean}`;
}

/**
 * Pick the best OG/banner image from a README. Accepts an already-fetched
 * README string to avoid a second network request when the caller has one.
 */
export async function fetchGitHubOGImage(
  owner: string,
  name: string,
  options?: { readme?: string | null },
): Promise<string | null> {
  try {
    const readme = options?.readme ?? (await fetchGitHubReadme(owner, name));
    if (!readme) return null;

    const urls: { url: string; alt: string }[] = [];

    // Extract from Markdown image syntax
    for (const m of readme.matchAll(MD_IMG_RE)) {
      urls.push({
        url: resolveReadmeUrl(m[2].trim(), owner, name),
        alt: (m[1] || "").trim(),
      });
    }

    // Extract from HTML <img> tags (handles any attribute order, single/double quotes)
    for (const m of readme.matchAll(README_IMG_RE)) {
      const src = resolveReadmeUrl(m[2].trim(), owner, name);
      const altMatch = m[0].match(/alt=(["'])(.*?)\1/i);
      urls.push({ url: src, alt: (altMatch ? altMatch[2] : "").trim() });
    }

    let githubFallback: string | null = null;
    let anyFallback: string | null = null;
    for (const { url, alt } of urls) {
      if (isBadge(url)) continue;
      if (SCREENSHOT_KEYWORDS.test(alt) || SCREENSHOT_KEYWORDS.test(url)) {
        return url;
      }
      if (isGitHubHosted(url) && !githubFallback) githubFallback = url;
      if (!anyFallback) anyFallback = url;
    }
    if (githubFallback) return githubFallback;
    if (anyFallback) return anyFallback;

    return null;
  } catch {
    return null;
  }
}

export async function fetchGitHubReadme(
  owner: string,
  name: string,
): Promise<string | null> {
  const token = process.env.GITHUB_TOKEN;
  const headers: Record<string, string> = { "User-Agent": "karakeep" };
  if (token) headers.Authorization = `Bearer ${token}`;

  for (const branch of ["main", "master"]) {
    try {
      const res = await fetch(
        `https://raw.githubusercontent.com/${encodeURIComponent(owner)}/${encodeURIComponent(name)}/${branch}/README.md`,
        { headers },
      );
      if (res.ok) return await res.text();
    } catch {
      // ignore
    }
  }

  try {
    const res = await fetch(
      `${GITHUB_API_BASE}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(name)}/readme`,
      { headers: { ...headers, Accept: "application/vnd.github.v3.raw" } },
    );
    if (res.ok) return await res.text();
  } catch {
    // ignore
  }

  return null;
}

/**
 * Truncate to at most `maxChars` Unicode code points (not UTF-16 code units),
 * so that a surrogate pair (emoji) is never split in half.
 */
export function preprocessReadme(raw: string, maxChars = 8000): string {
  const lines = raw.split("\n").filter((l) => l.trim());
  const cleaned = lines
    .map((l) => l.replace(/!\[.*?\]\(.*?\)/g, "").trim())
    .filter(Boolean)
    .join("\n");
  // Slice by code point to avoid splitting surrogate pairs (emoji / rare CJK).
  const codePoints = Array.from(cleaned);
  return codePoints.length > maxChars
    ? codePoints.slice(0, maxChars).join("")
    : cleaned;
}

/**
 * Build the single AI prompt that produces BOTH the human summary and the
 * agent dossier in one LLM call. The rule-engine category and tags are fed
 * in as strong priors so the model reinforces rather than re-derives them.
 */
function buildDeepDivePrompt(params: {
  name: string;
  description: string | null;
  language: string | null;
  stars: number | null;
  topics: string[];
  readmeContent: string;
  category: string;
  categoryLabel: string;
  humanTags: string[];
  agentTags: string[];
  valueScore: "high" | "mid" | "low";
  sourceContext: string | null;
}): string {
  const sourceBlock = params.sourceContext
    ? `\n有人这样分享过它（原始分享文，可能是推文）：\n"${params.sourceContext.slice(0, 600)}"\n`
    : "";

  return `你是一个技术分析专家。分析以下 GitHub 项目，返回纯 JSON（不要 markdown 代码块，不要任何其他文字）。

项目名称：${params.name}
官方描述：${params.description ?? "无"}
编程语言：${params.language ?? "未知"}
Stars：${params.stars ?? "未知"}
GitHub Topics：${params.topics.join(", ") || "无"}
${sourceBlock}
规则引擎预分类（强信号，作为参考，但你可以修正）：
- 类别：${params.category}（${params.categoryLabel}）
- 人类标签：${params.humanTags.join(", ") || "无"}
- Agent 标签：${params.agentTags.join(", ") || "无"}

README 内容：
${params.readmeContent}

分析要求：
1. GitHub Topics 是最可靠的分类线索，先看 topics 再看 README。
2. 常见 topics 映射参考：alist/aliyunpan/baidupan/clouddrive/nas → 云盘管理。
3. 结合 README 确认核心功能、技术栈、成熟度。
4. 技术/产品原名（如 skills、cli、react、docker）不要翻译成中文。

请返回以下 JSON（严格 JSON，字段名不可变）：
{
  "humanSummary": "30-60字中文通俗简介，让非技术用户也能看懂，不要重复项目名称（卡片标题已显示）",
  "valueScore": "high | mid | low（项目价值：high=首创/同类最佳/高增长，mid=有用但非突出，low=过时/简单/小众）",
  "dossier": {
    "oneLiner": "一句话精准概括项目定位（20字内）",
    "overview": "200-500字完整项目介绍，面向 AI Agent 阅读：目的、核心功能、架构特点、使用方式",
    "category": "项目分类（如云盘管理、前端框架、CLI工具、DevOps、数据库等）",
    "keyFeatures": ["核心功能点，每点10字以内"],
    "techStack": ["技术栈，如 Go", "Vue.js", "PostgreSQL"],
    "useCases": ["适用场景"],
    "alternatives": ["替代品/竞品，项目名即可"],
    "pros": ["主要优势"],
    "cons": ["主要局限"],
    "knowledgeTags": ["5-10个用于搜索的标签"],
    "maturity": "active | stable | inactive",
    "confidence": "high | medium | low"
  }
}`;
}

/** Best-effort extraction of a JSON object from an LLM response. */
function parseJsonFromLLMResponse(response: string): unknown {
  const trimmed = response.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    const jsonBlockRegex = /```(?:json)?\s*(\{[\s\S]*\})\s*```/i;
    const match = trimmed.match(jsonBlockRegex);
    if (match) {
      return JSON.parse(match[1]);
    }
    // Last resort: grab the first {...} balanced span.
    const start = trimmed.indexOf("{");
    const end = trimmed.lastIndexOf("}");
    if (start !== -1 && end > start) {
      return JSON.parse(trimmed.slice(start, end + 1));
    }
    throw new Error("No JSON found in LLM response");
  }
}

/**
 * Determine value score based on stars. This is the deterministic fallback
 * used both as a prior for the AI prompt and to validate the AI's output.
 */
function determineValueScore(stars: number | null): "high" | "mid" | "low" {
  if (stars === null) return "mid";
  if (stars >= 1000) return "high";
  if (stars >= 100) return "mid";
  return "low";
}

/**
 * Build the humanTags / agentTags from rule-engine results + GitHub topics,
 * WITHOUT an extra LLM call. Returns deduplicated arrays.
 */
function buildTagsFromRules(
  ruleResults: ReturnType<typeof classifyByRules>,
  ghTopics: string[],
): { humanTags: string[]; agentTags: string[]; primaryCategory: string } {
  const topRule = ruleResults[0];
  const primaryCategory = topRule?.category ?? "other";

  const humanTags: string[] = [];
  const agentTags: string[] = [];
  if (topRule && topRule.confidence >= 20) {
    humanTags.push(primaryCategory);
    agentTags.push(primaryCategory);
  }
  for (const rule of ruleResults) {
    if (rule.category === primaryCategory) continue;
    if (rule.confidence >= 20) {
      humanTags.push(rule.category);
      agentTags.push(rule.category);
    }
  }
  // GitHub topics are high-quality agent search tags
  for (const topic of ghTopics) {
    if (!agentTags.includes(topic)) agentTags.push(topic);
  }
  return { humanTags, agentTags, primaryCategory };
}

/**
 * Extract supplementary tags from project description and README content
 * using deterministic keyword matching (no AI, no prompt).
 */
const TAG_KEYWORDS: Record<string, string> = {
  codex: "codex",
  agent: "agent",
  cli: "cli",
  api: "api",
  react: "react",
  vue: "vue",
  svelte: "svelte",
  docker: "docker",
  kubernetes: "kubernetes",
  python: "python",
  typescript: "typescript",
  javascript: "javascript",
  rust: "rust",
  go: "go",
  "machine learning": "machine-learning",
  "deep learning": "deep-learning",
  database: "database",
  plugin: "plugin",
  extension: "extension",
  framework: "framework",
  library: "library",
  template: "template",
  dashboard: "dashboard",
  automation: "automation",
  testing: "testing",
  deploy: "deploy",
  monitor: "monitoring",
  search: "search",
  auth: "authentication",
  "open source": "open-source",
};

function extractTagsFromText(text: string): string[] {
  const tags: string[] = [];
  const lower = text.toLowerCase();
  for (const [keyword, tag] of Object.entries(TAG_KEYWORDS)) {
    if (lower.includes(keyword) && !tags.includes(tag)) {
      tags.push(tag);
    }
  }
  return tags;
}

/**
 * THE canonical GitHub deep-dive pipeline (rules + a single AI call).
 *
 * Replaces the three previously overlapping implementations:
 *  - inference/classify.ts `classifyGitHubProject` (deleted)
 *  - workers/githubDeepDiveWorker.ts `runDeepDive` (now a thin wrapper)
 *  - this file's previous `runGitHubDeepDive` (which skipped the dossier)
 *
 * Produces: humanSummary, dossier, tags, agentTags, valueScore, archive flag.
 */
export async function runGitHubDeepDive(params: {
  bookmarkId: string;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  db: any;
}): Promise<{ success: boolean; error?: string }> {
  const { bookmarkId, db } = params;

  const gh = await db.query.githubProjects.findFirst({
    where: eq(githubProjects.bookmarkId, bookmarkId),
  });
  if (!gh) {
    return { success: false, error: "GitHub project not found" };
  }

  await db
    .update(githubProjects)
    .set({ aiStatus: "pending" })
    .where(eq(githubProjects.bookmarkId, bookmarkId));

  // ── Step 0: Refresh GitHub metadata if topics are empty ──
  let ghTopics = gh.topics ?? [];
  let ghStars = gh.stars;
  let ghDescription = gh.description;
  let ghLanguage = gh.language;
  if (!ghTopics.length) {
    try {
      const meta = await fetchGitHubRepoMetadata(gh.owner, gh.name);
      if (meta) {
        ghTopics = meta.topics;
        ghStars = meta.stars;
        ghDescription = meta.description ?? gh.description;
        ghLanguage = meta.language ?? gh.language;
        await db
          .update(githubProjects)
          .set({
            topics: meta.topics,
            stars: meta.stars,
            description: meta.description,
            language: meta.language,
            lastFetchedAt: new Date(),
          })
          .where(eq(githubProjects.bookmarkId, bookmarkId));
      }
    } catch (e) {
      // Metadata refresh is best-effort; record it but keep going with what we have.
      logger.warn(
        `[github] Metadata refresh failed for ${gh.fullName}: ${e instanceof Error ? e.message : e}`,
      );
    }
  }

  // ── Step 1: Rule-based classification (deterministic, no AI) ──
  const ruleResults = classifyByRules({
    topics: ghTopics,
    description: ghDescription ?? "",
    name: gh.name,
  });
  const { humanTags, agentTags, primaryCategory } = buildTagsFromRules(
    ruleResults,
    ghTopics,
  );
  const categoryLabel =
    TAXONOMY[primaryCategory as keyof typeof TAXONOMY]?.label ?? "其他";

  // Value score from stars (deterministic prior)
  const ruleValueScore = determineValueScore(ghStars);

  // ── Step 2: Get source context (bookmarker text) ──
  let sourceContext: string | null = null;
  try {
    const rec = await db.query.projectRecommendations.findFirst({
      where: eq(projectRecommendations.projectId, gh.id),
      columns: { recommendationContext: true },
    });
    if (rec?.recommendationContext) {
      sourceContext = rec.recommendationContext;
    }
  } catch (e) {
    logger.warn(
      `[github] Failed to read projectRecommendations for ${gh.fullName}: ${e instanceof Error ? e.message : e}`,
    );
  }

  // ── Step 3: Get README ──
  let readmeContent = "(README not available)";
  try {
    const readme = await fetchGitHubReadme(gh.owner, gh.name);
    if (readme) readmeContent = preprocessReadme(readme);
  } catch (e) {
    logger.warn(
      `[github] README fetch failed for ${gh.fullName}: ${e instanceof Error ? e.message : e}`,
    );
  }

  // Extract supplementary tags from description + README (deterministic)
  const extractedTags = extractTagsFromText(
    (ghDescription ?? "") + " " + readmeContent,
  );
  for (const tag of extractedTags) {
    if (!humanTags.includes(tag)) humanTags.push(tag);
    if (!agentTags.includes(tag)) agentTags.push(tag);
  }

  // ── Step 4: Single AI call — humanSummary + dossier together ──
  let humanSummary = ghDescription ?? "";
  let dossier: AgentDossier | null = null;
  let valueScore: "high" | "mid" | "low" = ruleValueScore;

  try {
    const { buildInferenceClient } = await import("./ai-providers");
    const inferenceClient = await buildInferenceClient(db);

    if (inferenceClient) {
      const prompt = buildDeepDivePrompt({
        name: gh.name,
        description: ghDescription,
        language: ghLanguage,
        stars: ghStars,
        topics: ghTopics,
        readmeContent,
        category: primaryCategory,
        categoryLabel,
        humanTags,
        agentTags,
        valueScore: ruleValueScore,
        sourceContext,
      });

      const result = await inferenceClient.inferFromText(prompt, {
        // Force JSON object mode; we parse + validate ourselves below.
        schema: null,
      });

      const parsed = parseJsonFromLLMResponse(result.response) as {
        humanSummary?: string;
        valueScore?: string;
        dossier?: AgentDossier;
      };

      if (parsed.humanSummary && typeof parsed.humanSummary === "string") {
        humanSummary = parsed.humanSummary.trim();
      }
      if (
        parsed.valueScore === "high" ||
        parsed.valueScore === "mid" ||
        parsed.valueScore === "low"
      ) {
        valueScore = parsed.valueScore;
      }
      if (parsed.dossier && parsed.dossier.oneLiner) {
        dossier = parsed.dossier;
      }
    }
  } catch (e) {
    // AI failed — fall back to GitHub description + rule-based tags.
    logger.warn(
      `[github] AI deep dive failed for ${gh.fullName}: ${e instanceof Error ? e.message : e}`,
    );
    humanSummary = ghDescription ?? `${gh.name} 是一个 ${categoryLabel} 类项目`;
  }

  // ── Step 5: Archive logic (unified) ──
  // Low value (either AI-scored or rule-based stars<100) → archive.
  let archived = false;
  let archiveReason: string | null = null;
  if (valueScore === "low") {
    archived = true;
    archiveReason = "低价值项目（stars<100 或 AI 评分 low），自动归档";
  }

  // ── Step 6: Persist ──
  await db
    .update(githubProjects)
    .set({
      tags: humanTags.length > 0 ? humanTags : undefined,
      agentTags: agentTags.length > 0 ? agentTags : null,
      humanSummary: humanSummary || undefined,
      agentDossier: dossier,
      valueScore: valueScore as "high" | "mid" | "low",
      archived,
      archiveReason,
      aiStatus: "completed",
    })
    .where(eq(githubProjects.bookmarkId, bookmarkId));

  logger.info(
    `[github] Deep dive completed for ${gh.fullName}: score=${valueScore}, archived=${archived}, dossier=${dossier ? "yes" : "no"}`,
  );

  return { success: true };
}
