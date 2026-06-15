import { eq } from "drizzle-orm";
import { githubProjects } from "@karakeep/db/schema";
import type { AgentDossier } from "@karakeep/shared/types/bookmarks";
import { InferenceClientFactory } from "@karakeep/shared/inference";

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

export function buildDeepDivePrompt(meta: {
  name: string;
  description: string | null;
  language: string | null;
  stars: number | null;
  topics: string[] | null;
  readmeContent: string;
}): string {
  return `你是一个技术分析专家。分析以下 GitHub 项目的 README 和元数据，返回纯 JSON。

项目名称：${meta.name}
官方描述：${meta.description ?? "无"}
编程语言：${meta.language ?? "未知"}
Stars：${meta.stars ?? "未知"}
Topics：${meta.topics?.join(", ") ?? "无"}

README 内容：
${meta.readmeContent}

分析要求：
1. 先理解这个项目到底「是什么」——它的本质分类（不要只看名字）
2. 标签要回答「这个项目是什么」，不是「它用了什么技术」
   - skills 项目 → "技能"
   - Agent 框架 → "智能体"
   - CLI 工具 → "命令行" 或 "工具"
3. 只用中文标签，非必要不用英文
4. 结合 README 确认核心用途

请返回以下 JSON（不要任何其他文字，严格 JSON 格式）：
{
  "humanSummary": "30-60字中文通俗简介，让非技术用户也能看懂这个项目是做什么的，不要重复项目名称（卡片标题已经显示了）",
  "valueScore": "high 或 mid 或 low（项目价值评分：high=首创/同类最佳/高增长，mid=有用但非突出，low=过时/简单/小众）",
  "tags": ["3-5个中文标签，每个是独立概念，按重要性从高到低。最重要标签放第一位。不能包含'/'组合词或整句描述。标签回答\"这个项目是什么\"，比如：["技能","智能体","自动化"] 或 ["运维","数据库","监控"]。非必要不用英文"],
  "dossier": {
    "oneLiner": "一句话精准概括项目定位（20字内）",
    "overview": "200-500字的完整项目介绍，面向 AI Agent 阅读，包含：项目目的、核心功能、架构特点、使用方式",
    "category": "项目分类（如云盘管理、前端框架、CLI工具、DevOps、数据库等）",
    "keyFeatures": ["核心功能点列表，每点10字以内"],
    "techStack": ["技术栈列表，如Go", "Vue.js", "PostgreSQL"],
    "useCases": ["适用场景列表"],
    "alternatives": ["替代品或竞品列表，项目名即可"],
    "pros": ["主要优势列表"],
    "cons": ["主要局限列表"],
    "knowledgeTags": ["5-10个英文标签，每个精准描述项目用途。Agent 搜索用。例如：["goal-instructions","task-decomposition","codex-agent","llm-prompting"]"],
    "maturity": "active 或 stable 或 inactive",
    "confidence": "high 或 medium 或 low"
  }
}`;
}

/**
 * Run a GitHub deep dive analysis inline (no queue/worker needed).
 */
export async function runGitHubDeepDive(params: {
  bookmarkId: string;
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

  let readmeContent = "(README not available)";
  try {
    const readme = await fetchGitHubReadme(gh.owner, gh.name);
    if (readme) readmeContent = preprocessReadme(readme);
  } catch {}

  const dbProviderConfig = await db.query.providerConfig.findFirst();
  const inferenceClient = InferenceClientFactory.build({
    apiKey: dbProviderConfig?.apiKey ?? undefined,
    baseURL: dbProviderConfig?.baseUrl ?? undefined,
    textModel: dbProviderConfig?.textModel ?? undefined,
    imageModel: dbProviderConfig?.imageModel ?? undefined,
    outputSchema: dbProviderConfig?.outputSchema as any,
  });
  if (!inferenceClient) {
    await db
      .update(githubProjects)
      .set({ aiStatus: "failed" })
      .where(eq(githubProjects.bookmarkId, bookmarkId));
    return { success: false, error: "No AI inference client configured" };
  }

  const prompt = buildDeepDivePrompt({
    name: gh.name,
    description: gh.description,
    language: gh.language,
    stars: gh.stars,
    topics: gh.topics,
    readmeContent,
  });

  let result;
  try {
    result = await inferenceClient.inferFromText(prompt, { schema: null });
  } catch (e: any) {
    await db
      .update(githubProjects)
      .set({ aiStatus: "failed" })
      .where(eq(githubProjects.bookmarkId, bookmarkId));
    return { success: false, error: `AI inference failed: ${e.message ?? e}` };
  }

  let humanSummary: string;
  let dossier: AgentDossier | null;
  let valueScore = "unscored";
  let tags: string[] = [];

  try {
    const parsed = JSON.parse(result.response);
    humanSummary = parsed.humanSummary ?? "";
    dossier = parsed.dossier;
    valueScore = parsed.valueScore ?? "unscored";
    tags = Array.isArray(parsed.tags) ? parsed.tags : [];
  } catch {
    await db
      .update(githubProjects)
      .set({ aiStatus: "failed" })
      .where(eq(githubProjects.bookmarkId, bookmarkId));
    return { success: false, error: "Failed to parse AI response as JSON" };
  }

  if (!dossier || !dossier.oneLiner) {
    await db
      .update(githubProjects)
      .set({ aiStatus: "failed" })
      .where(eq(githubProjects.bookmarkId, bookmarkId));
    return {
      success: false,
      error: "AI response missing required dossier fields",
    };
  }

  let archived = false;
  let archiveReason: string | null = null;
  if (valueScore === "low") {
    archived = true;
    archiveReason = "AI 评分为低价值，自动归档";
  } else if (valueScore === "unscored" && gh.stars !== null && gh.stars < 100) {
    archived = true;
    archiveReason = "star<100 且无 AI 评分，自动归档";
  }

  await db
    .update(githubProjects)
    .set({
      humanSummary: humanSummary || undefined,
      tags: tags.length > 0 ? tags : undefined,
      agentDossier: dossier,
      agentTags: dossier.knowledgeTags ?? null,
      valueScore: valueScore as any,
      archived,
      archiveReason,
      aiStatus: "completed",
    })
    .where(eq(githubProjects.bookmarkId, bookmarkId));

  return { success: true };
}
