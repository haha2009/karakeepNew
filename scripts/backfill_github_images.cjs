const path = require("path");
const crypto = require("crypto");
const Database = require(
  path.join(process.cwd(), "node_modules/.pnpm/better-sqlite3@11.3.0/node_modules/better-sqlite3")
);

// Source DB for GitHub bookmark IDs
const db = new Database("/data/db.db");
const rows = db.prepare(
  "SELECT bl.id FROM bookmarkLinks bl INNER JOIN githubProjects gp ON gp.bookmarkId = bl.id WHERE bl.imageUrl IS NULL"
).all();
console.log(`Enqueuing crawl for ${rows.length} GitHub bookmarks...`);

// Direct insert into queue.db tasks table
const qdb = new Database("/data/queue.db");
const now = Date.now();
let count = 0;

for (const row of rows) {
  const allocationId = crypto.randomUUID();
  const idempotencyKey = `crawl-${row.id}`;
  
  qdb.prepare(`
    INSERT INTO tasks (queue, payload, createdAt, status, allocationId, numRunsLeft, maxNumRuns, idempotencyKey, priority, availableAt)
    VALUES (?, ?, ?, 'pending', ?, 5, 5, ?, 0, ?)
  `).run(
    "link_crawler_queue",
    JSON.stringify({ bookmarkId: row.id }),
    Math.floor(now / 1000),
    allocationId,
    idempotencyKey,
    now,
  );
  count++;
}

console.log(`Done! Enqueued ${count} crawl jobs.`);
qdb.close();
db.close();
