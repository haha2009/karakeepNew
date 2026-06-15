import { eq } from "drizzle-orm";
import { githubProjects, projectRecommendations } from "@karakeep/db/schema";
import { InferenceClientFactory } from "@karakeep/shared/inference";
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

export async function fetchGitHubOGImage(
  owner: string,
  name: string,
): Promise<string | null> {
  try {
    const readme = await fetchGitHubReadme(owner, name);
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
      `https://api.github.com/repos/${encodeURIComponent(owner)}/${encodeURIComponent(name)}/readme`,
      { headers: { ...headers, Accept: "application/vnd.github.v3.raw" } },
    );
    if (res.ok) return await res.text();
  } catch {
    // ignore
  }

  return null;
}

export async function generateGitHubHumanSummary(
  meta: GitHubRepoMetadata,
): Promise<string | null> {
  const apiKey = process.env.OPENAI_API_KEY;
  const baseUrl = process.env.OPENAI_BASE_URL;
  const model = process.env.INFERENCE_TEXT_MODEL || "gpt-4.1-mini";
  if (!apiKey || !baseUrl) return null;

  const prompt = `你是一个技术翻译官。请用通俗易懂的中文（让不懂技术的人也能看懂）解释下面这个 GitHub 项目是做什么的。

项目名称：${meta.name}
官方描述：${meta.description ?? "无"}
编程语言：${meta.language ?? "未知"}
标签：${meta.topics.join(", ") || "无"}

标签是理解项目的关键线索，请先分析标签含义再下结论。常见的 Go 项目标签映射：
- alist / aliyunpan / baidupan / clouddrive / nas → 网盘聚合管理
- 其他标签按实际含义理解

要求：
- 一句话讲清楚这个项目是做什么的，先自问：标签共同指向什么领域？
- 不要机翻，要真正理解后用自己的话写
- 让不懂技术的人也能看懂
- 控制在 30-60 字`;

  try {
    const response = await fetch(`${baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        messages: [{ role: "user", content: prompt }],
        max_tokens: 200,
        temperature: 0.5,
      }),
    });
    if (!response.ok) return null;
    const data = await response.json();
    return data.choices?.[0]?.message?.content?.trim() ?? null;
  } catch {
    return null;
  }
}

export function preprocessReadme(raw: string): string {
  const lines = raw.split("\n").filter((l) => l.trim());
  const cleaned = lines
    .map((l) => l.replace(/!\[.*?\]\(.*?\)/g, "").trim())
    .filter(Boolean)
    .join("\n");
  return cleaned.length > 8000 ? cleaned.slice(0, 8000) : cleaned;
}

export function buildSynthesisPrompt(params: {
  name: string;
  description: string | null;
  stars: number | null;
  topics: string[] | null;
  readmeContent: string;
  /** The bookmaker's original sharing text (e.g. tweet content) */
  sourceContext: string | null;
  /** Deterministic category from rules engine */
  category: string;
  /** Human-readable tags */
  tags: string[];
  /** Agent search tags */
  agentTags: string[];
  /** Value score from rules */
  valueScore: string;
}): string {
  let prompt = `请用一句话（30-50 字）说清楚这个项目是什么。只输出这句话，不要别的。

# 项目信息
名称：${params.name}
描述：${params.description ?? "无"}
标签：${params.tags.join("、")}
类别：${params.category}

`;

  if (params.sourceContext) {
    prompt += `有人这样分享过它：
"${params.sourceContext.slice(0, 600)}"

`;
  }

  prompt += `README 关键内容：
${params.readmeContent.slice(0, 3000)}

要求：一句话（30-50 字），像朋友推荐好用的工具那样自然。
注意：项目类别和标签中的英文词（如 skills、cli、agent、react 等）是固定技术术语，不要翻译成中文。
只输出这句话。`;

  return prompt;
}

/**
 * Determine value score based on stars and other signals.
 */
function determineValueScore(stars: number | null): "high" | "mid" | "low" {
  if (stars === null) return "mid";
  if (stars >= 1000) return "high";
  if (stars >= 100) return "mid";
  return "low";
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
 * Run a GitHub deep dive analysis inline (no queue/worker needed).
 * Uses rules for classification (deterministic, no AI prompt),
 * then AI only for summary synthesis combining source context + GitHub data.
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
  if (!ghTopics.length) {
    try {
      const meta = await fetchGitHubRepoMetadata(gh.owner, gh.name);
      if (meta) {
        ghTopics = meta.topics;
        ghStars = meta.stars;
        ghDescription = meta.description ?? gh.description;
        await db
          .update(githubProjects)
          .set({
            topics: meta.topics,
            stars: meta.stars,
            description: meta.description,
            lastFetchedAt: new Date(),
          })
          .where(eq(githubProjects.bookmarkId, bookmarkId));
      }
    } catch {
      /* ignore: projectRecommendations table might not exist yet */
    }
  }

  // ── Step 1: Rule-based classification (deterministic, no AI) ──
  const ruleResults = classifyByRules({
    topics: ghTopics,
    description: ghDescription ?? "",
    name: gh.name,
  });
  const topRule = ruleResults[0];
  const primaryCategory = topRule?.category ?? "other";
  const categoryLabel = TAXONOMY[primaryCategory]?.label ?? "其他";

  // Build humanTags from rule results
  // Use category ID (English) for technical terms that shouldn't be translated
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
  // Add GitHub topics as agentTags for Agent search
  for (const topic of ghTopics) {
    if (!agentTags.includes(topic)) {
      agentTags.push(topic);
    }
  }

  // Value score from stars (no AI)
  const valueScore = determineValueScore(ghStars);

  // ── Step 2: Get source context (bookmaker text) ──
  let sourceContext: string | null = null;
  try {
    const rec = await db.query.projectRecommendations.findFirst({
      where: eq(projectRecommendations.projectId, gh.id),
      columns: { recommendationContext: true },
    });
    if (rec?.recommendationContext) {
      sourceContext = rec.recommendationContext;
    }
  } catch {
    // projectRecommendations table might not exist yet
  }

  // ── Step 3: Get README ──
  let readmeContent = "(README not available)";
  try {
    const readme = await fetchGitHubReadme(gh.owner, gh.name);
    if (readme) readmeContent = preprocessReadme(readme);
  } catch {
    /* ignore: README fetch failure */
  }

  // Extract supplementary tags from description + README (deterministic, no AI)
  const descriptionText = ghDescription ?? "";
  const extractedTags = extractTagsFromText(
    descriptionText + " " + readmeContent,
  );
  for (const tag of extractedTags) {
    if (!humanTags.includes(tag)) {
      humanTags.push(tag);
    }
    if (!agentTags.includes(tag)) {
      agentTags.push(tag);
    }
  }

  // ── Step 4: AI synthesis for humanSummary only ──
  let humanSummary = gh.description ?? "";
  try {
    const synthesisPrompt = buildSynthesisPrompt({
      name: gh.name,
      description: ghDescription,
      stars: ghStars,
      topics: ghTopics,
      readmeContent,
      sourceContext,
      category: primaryCategory,
      tags: humanTags,
      agentTags,
      valueScore,
    });

    const dbProviderConfig = await db.query.providerConfig.findFirst();
    const inferenceClient = InferenceClientFactory.build({
      apiKey: dbProviderConfig?.apiKey ?? undefined,
      baseURL: dbProviderConfig?.baseUrl ?? undefined,
      textModel: dbProviderConfig?.textModel ?? undefined,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      outputSchema: "plain" as any,
    });

    if (inferenceClient) {
      const result = await inferenceClient.inferFromText(synthesisPrompt, {});
      const text = result.response.trim();
      if (text) humanSummary = text;
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } catch (e: any) {
    // AI failed — fall back to GitHub description
    logger.warn(
      `[github] AI synthesis failed for ${gh.fullName}: ${e.message ?? e}`,
    );
    humanSummary = ghDescription ?? `${gh.name} 是一个 ${categoryLabel} 类项目`;
  }

  // ── Step 5: Archive logic ──
  let archived = false;
  let archiveReason: string | null = null;
  if (valueScore === "low") {
    archived = true;
    archiveReason = "低价值（stars<100），自动归档";
  }

  // ── Step 6: Save results ──
  await db
    .update(githubProjects)
    .set({
      tags: humanTags.length > 0 ? humanTags : undefined,
      agentTags: agentTags.length > 0 ? agentTags : null,
      humanSummary: humanSummary || undefined,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      valueScore: valueScore as any,
      archived,
      archiveReason,
      aiStatus: "completed",
    })
    .where(eq(githubProjects.bookmarkId, bookmarkId));

  return { success: true };
}
