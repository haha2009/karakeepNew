import "dotenv/config";
import Database from "better-sqlite3";
import serverConfig from "@karakeep/shared/config";
import { mkdir, writeFile } from "fs/promises";
import path from "path";
import crypto from "crypto";

const ASSETS_DIR = serverConfig.assetsDir;
const DB_PATH = path.join(serverConfig.dataDir, "db.db");

function extractTweetId(url: string): string | null {
  const match = url.match(/(?:x\.com|twitter\.com)\/\w+\/status\/(\d+)/i);
  return match?.[1] ?? null;
}

async function fetchTwitterImage(tweetId: string): Promise<string | null> {
  try {
    const resp = await fetch(
      `https://api.vxtwitter.com/Twitter/status/${tweetId}`,
      { signal: AbortSignal.timeout(10000) },
    );
    if (!resp.ok) return null;
    const data = (await resp.json()) as {
      media_extended?: {
        type: string;
        url: string;
        thumbnail_url?: string;
      }[];
    };
    if (!data.media_extended?.length) return null;
    const m = data.media_extended[0];
    // Videos have a separate thumbnail_url; images use url directly
    return m.type === "video" && m.thumbnail_url ? m.thumbnail_url : m.url;
  } catch {
    return null;
  }
}

async function fetchTwitterAvatar(tweetId: string): Promise<string | null> {
  try {
    const resp = await fetch(
      `https://api.vxtwitter.com/Twitter/status/${tweetId}`,
      { signal: AbortSignal.timeout(10000) },
    );
    if (!resp.ok) return null;
    const data = (await resp.json()) as { user_profile_image_url?: string };
    return data.user_profile_image_url ?? null;
  } catch {
    return null;
  }
}

async function fetchOgImageUrl(url: string): Promise<string | null> {
  try {
    const resp = await fetch(url, {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (compatible; Karakeep/1.0; +https://karakeep.app)",
        Accept: "text/html",
      },
      redirect: "follow",
      signal: AbortSignal.timeout(15000),
    });
    const html = await resp.text();
    const ogMatch = html.match(
      /<meta\s+property=["']og:image["']\s+content=["']([^"']+)["']/i,
    );
    if (ogMatch) return ogMatch[1];
    const twMatch = html.match(
      /<meta\s+name=["']twitter:image["']\s+content=["']([^"']+)["']/i,
    );
    if (twMatch) return twMatch[1];
    return null;
  } catch {
    return null;
  }
}

async function downloadImage(imageUrl: string): Promise<Buffer | null> {
  try {
    const resp = await fetch(imageUrl, {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Karakeep/1.0",
      },
      redirect: "follow",
      signal: AbortSignal.timeout(30000),
    });
    if (!resp.ok) return null;
    const ct = resp.headers.get("content-type") ?? "";
    if (!ct.startsWith("image/")) return null;
    const buf = Buffer.from(await resp.arrayBuffer());
    return buf.length < 100 ? null : buf;
  } catch {
    return null;
  }
}

async function main() {
  const sqlite = new Database(DB_PATH);
  sqlite.pragma("journal_mode = WAL");
  sqlite.pragma("foreign_keys = ON");

  const links = sqlite
    .prepare(
      `SELECT bl.id AS linkId, bl.url, b.userId, b.id AS bookmarkId
       FROM bookmarkLinks bl
       JOIN bookmarks b ON b.id = bl.id
       WHERE b.userId = 'j7wbv3wle3eklvqvlmc6crxg'
         AND bl.imageUrl IS NULL
         AND bl.crawlStatus = 'failure'`,
    )
    .all() as {
    linkId: string;
    url: string;
    userId: string;
    bookmarkId: string;
  }[];

  console.log(`Found ${links.length} links missing images.`);

  const delStmt = sqlite.prepare(
    `DELETE FROM assets WHERE bookmarkId = ? AND assetType = 'linkScreenshot'`,
  );
  const insStmt = sqlite.prepare(
    `INSERT INTO assets (id, assetType, size, contentType, fileName, bookmarkId, userId)
     VALUES (?, 'linkBannerImage', ?, 'image/jpeg', 'og-image.jpg', ?, ?)`,
  );

  let success = 0;
  let skipped = 0;

  for (const link of links) {
    const tweetId = extractTweetId(link.url);
    let imageUrl: string | null = null;

    if (tweetId) {
      console.log(`\n[${link.linkId.slice(0, 8)}] Twitter -> vxtwitter API...`);
      imageUrl = await fetchTwitterImage(tweetId);
    }

    if (!imageUrl) {
      console.log(
        `[${link.linkId.slice(0, 8)}] Fetching og:image from HTML...`,
      );
      imageUrl = await fetchOgImageUrl(link.url);
    }

    if (!imageUrl && tweetId) {
      console.log(
        `[${link.linkId.slice(0, 8)}] No media — trying author avatar...`,
      );
      imageUrl = await fetchTwitterAvatar(tweetId);
    }

    if (!imageUrl) {
      console.log(`[${link.linkId.slice(0, 8)}] No image URL found.`);
      skipped++;
      continue;
    }

    process.stdout.write(`[${link.linkId.slice(0, 8)}] Downloading...`);
    const imgBuf = await downloadImage(imageUrl);

    if (!imgBuf) {
      console.log(` failed.`);
      skipped++;
      continue;
    }
    console.log(` ${imgBuf.length} bytes.`);

    const assetId = crypto.randomUUID();
    const assetDir = path.join(ASSETS_DIR, link.userId, assetId);
    await mkdir(assetDir, { recursive: true });
    await writeFile(path.join(assetDir, "asset.bin"), imgBuf);
    await writeFile(
      path.join(assetDir, "metadata.json"),
      JSON.stringify({
        contentType: "image/jpeg",
        fileName: "og-image.jpg",
      }),
    );

    delStmt.run(link.bookmarkId);
    insStmt.run(assetId, imgBuf.length, link.bookmarkId, link.userId);

    console.log(
      `[${link.linkId.slice(0, 8)}] Saved: ${assetId.slice(0, 8)} (${imgBuf.length} bytes)`,
    );
    success++;
  }

  sqlite.close();
  console.log(`\nDone! ${success} images saved, ${skipped} skipped.`);
}

main().catch(console.error);
