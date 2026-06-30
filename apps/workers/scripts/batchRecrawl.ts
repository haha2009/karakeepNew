/**
 * Batch recrawl: runs on the production server via `tsx scripts/batchRecrawl.ts`.
 * Directly queries the SQLite DB and enqueues LowPriorityCrawlerQueue jobs.
 *
 * Usage:
 * 在服务器上运行时需要设置 DATA_DIR 环境变量:
 *   DATA_DIR=/var/lib/karakeep/data tsx scripts/batchRecrawl.ts failure --limit=30
 *   DATA_DIR=/var/lib/karakeep/data tsx scripts/batchRecrawl.ts all
 */

import { db } from "@karakeep/db";
import { bookmarkLinks } from "@karakeep/db/schema";
import { LowPriorityCrawlerQueue } from "@karakeep/shared-server";
import { eq } from "drizzle-orm";

const LIMIT = parseInt(
  process.argv.find((a) => a.startsWith("--limit="))?.split("=")[1] ?? "0",
  10,
);

const ENV_FILE =
  process.env.ENV_FILE ??
  (process.env.DATA_DIR
    ? `${process.env.DATA_DIR}/.env`
    : "/var/lib/karakeep/data/.env");

async function main() {
  // Load .env if present (workers runtime doesn't always have all env vars)
  try {
    const fs = await import("node:fs");
    if (fs.existsSync(ENV_FILE)) {
      for (const line of fs.readFileSync(ENV_FILE, "utf8").split("\n")) {
        const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
        if (m && !(m[1] in process.env)) {
          process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
        }
      }
    }
  } catch {
    // ignore
  }

  const statusArg = process.argv[2];
  const VALID = ["failure", "pending", "success", "all"];
  if (!statusArg || !VALID.includes(statusArg)) {
    console.error(`Usage: tsx batchRecrawl.ts <${VALID.join("|")}> [--limit=N]`);
    process.exit(1);
  }

  const targetStatus =
    statusArg === "all" ? undefined : (statusArg as "failure" | "pending" | "success");

  console.log(`Loading .env from ${ENV_FILE} ...`);

  await LowPriorityCrawlerQueue.ensureInit();

  const rows = targetStatus
    ? await db.query.bookmarkLinks.findMany({
        columns: { id: true, url: true, crawlStatus: true },
        where: eq(bookmarkLinks.crawlStatus, targetStatus),
        limit: LIMIT || undefined,
      })
    : await db.query.bookmarkLinks.findMany({
        columns: { id: true, url: true, crawlStatus: true },
        limit: LIMIT || undefined,
      });

  console.log(`Found ${rows.length} bookmarks with crawlStatus=${targetStatus ?? "all"}`);

  if (rows.length === 0) return;

  let ok = 0,
    fail = 0;
  for (const b of rows) {
    try {
      await LowPriorityCrawlerQueue.enqueue(
        { bookmarkId: b.id, runInference: false },
        { priority: 10 },
      );
      ok++;
    } catch (e) {
      console.error(`  Enqueue failed ${b.id}: ${e}`);
      fail++;
    }
  }

  console.log(`Done. Enqueued: ${ok}, Failed: ${fail}`);
}

main().catch((e) => {
  console.error("Fatal:", e);
  process.exit(1);
});
