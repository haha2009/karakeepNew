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

const OG_IMAGE_RE = /<meta\s+property="og:image"\s+content="([^"]+)"\s*\/?>/i;
const README_IMG_SRC_RE = /<img[^>]*src="([^"]+)"[^>]*\/?\s*>/gi;

function resolveGitHubUrl(path: string, owner: string, name: string): string {
  if (path.startsWith("http://") || path.startsWith("https://")) return path;
  return `https://github.com${path.startsWith("/") ? "" : "/"}${path}`;
}

function isBadge(url: string): boolean {
  try {
    const hostname = new URL(url).hostname;
    if (
      ["img.shields.io", "badge.fury.io", "travis-ci.org", "circleci.com",
        "codecov.io", "coveralls.io", "goreportcard.com", "gitter.im",
        "discordapp.com"].some((d) => hostname.endsWith(d))
    ) return true;
    return false;
  } catch {
    return false;
  }
}

export async function fetchGitHubOGImage(
  owner: string,
  name: string,
): Promise<string | null> {
  try {
    const response = await fetch(
      `https://github.com/${encodeURIComponent(owner)}/${encodeURIComponent(name)}`,
      { headers: { "User-Agent": "karakeep" } },
    );
    if (!response.ok) return null;
    const html = await response.text();

    // Try to find first non-badge image inside README
    const readmeMatch = html.match(
      /<article[^>]*markdown-body[^>]*>[\s\S]*?<\/article>/i,
    );
    if (readmeMatch) {
      const readmeHtml = readmeMatch[0];
      const imgMatches = readmeHtml.matchAll(README_IMG_SRC_RE);
      for (const m of imgMatches) {
        const url = resolveGitHubUrl(m[1], owner, name);
        if (!isBadge(url)) return url;
      }
    }

    // Fall back to og:image
    const ogMatch = OG_IMAGE_RE.exec(html);
    return ogMatch?.[1] ?? null;
  } catch {
    return null;
  }
}

export async function generateGitHubHumanSummary(meta: GitHubRepoMetadata): Promise<string | null> {
  const apiKey = process.env.OPENAI_API_KEY;
  const baseUrl = process.env.OPENAI_BASE_URL;
  const model = process.env.INFERENCE_TEXT_MODEL || "gpt-4.1-mini";
  if (!apiKey || !baseUrl) return null;

  const prompt = `你是一个技术翻译官。请用通俗易懂的中文（让不懂技术的人也能看懂）解释下面这个 GitHub 项目是做什么的。

项目名称：${meta.name}
官方描述：${meta.description ?? "无"}
编程语言：${meta.language ?? "未知"}
标签：${meta.topics.join(", ") || "无"}

要求：
- 一句话讲清楚这个项目是做什么的
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
