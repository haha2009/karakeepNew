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
  };
}
