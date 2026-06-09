import Database from "better-sqlite3";

const GITHUB_TOKEN = "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";

function resolveReadmeUrl(url: string, owner: string, name: string): string {
  if (url.startsWith("http://") || url.startsWith("https://")) return url;
  const clean = url.startsWith("/") ? url.slice(1) : url;
  return `https://raw.githubusercontent.com/${encodeURIComponent(owner)}/${encodeURIComponent(name)}/main/${clean}`;
}

const SCREENSHOT_KEYWORDS =
  /screenshot|screenshots|demo|preview|showcase|展示|截图|预览/i;

function isBadge(url: string): boolean {
  try {
    const parsed = new URL(url);
    const hostname = parsed.hostname;
    const pathname = parsed.pathname;
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

async function fetchReadme(
  owner: string,
  name: string,
): Promise<string | null> {
  const headers: Record<string, string> = { "User-Agent": "karakeep" };
  headers.Authorization = `Bearer ${GITHUB_TOKEN}`;
  for (const branch of ["main", "master"]) {
    try {
      const res = await fetch(
        `https://raw.githubusercontent.com/${encodeURIComponent(owner)}/${encodeURIComponent(name)}/${branch}/README.md`,
        { headers },
      );
      if (res.ok) return await res.text();
    } catch {
      // ignore network errors, try next branch
    }
  }
  return null;
}

async function fetchOGImage(
  owner: string,
  name: string,
): Promise<string | null> {
  const readme = await fetchReadme(owner, name);
  if (!readme) return null;

  const urls: { url: string; alt: string }[] = [];

  const MD_IMG_RE = /!\[([^\]]*)\]\(([^)]+)\)/g;
  for (const m of readme.matchAll(MD_IMG_RE)) {
    urls.push({
      url: resolveReadmeUrl(m[2].trim(), owner, name),
      alt: (m[1] || "").trim(),
    });
  }

  const README_IMG_RE =
    /<img[^>]*src="([^"]+)"[^>]*alt="([^"]*)"[^>]*\/?\s*>/gi;
  for (const m of readme.matchAll(README_IMG_RE)) {
    urls.push({
      url: resolveReadmeUrl(m[1].trim(), owner, name),
      alt: (m[2] || "").trim(),
    });
  }

  let githubFallback: string | null = null;
  let anyFallback: string | null = null;
  for (const { url, alt } of urls) {
    if (isBadge(url)) continue;
    if (SCREENSHOT_KEYWORDS.test(alt) || SCREENSHOT_KEYWORDS.test(url))
      return url;
    if (isGitHubHosted(url) && !githubFallback) githubFallback = url;
    if (!anyFallback) anyFallback = url;
  }
  return githubFallback || anyFallback || null;
}

const dbPath = "/Users/claw/Projects/test/karakeep/data/db.db";
const db = new Database(dbPath);

const rows = db
  .prepare(
    `SELECT bl.id as bookmarkId, gp.owner, gp.name, gp.fullName, bl.imageUrl
     FROM githubProjects gp
     JOIN bookmarkLinks bl ON bl.id = gp.bookmarkId
     WHERE bl.imageUrl LIKE '%opengraph.githubassets%'`,
  )
  .all() as {
  bookmarkId: string;
  owner: string;
  name: string;
  fullName: string;
  imageUrl: string;
}[];

console.log(`Found ${rows.length} bookmarks with old OG images`);

for (const row of rows) {
  console.log(`[${row.fullName}] current: ${row.imageUrl}`);
  const ogUrl = await fetchOGImage(row.owner, row.name);
  console.log(`[${row.fullName}] new: ${ogUrl}`);
  if (ogUrl && ogUrl !== row.imageUrl) {
    db.prepare("UPDATE bookmarkLinks SET imageUrl = ? WHERE id = ?").run(
      ogUrl,
      row.bookmarkId,
    );
    console.log(`[${row.fullName}] updated ✓`);
  }
}

console.log("Done");
