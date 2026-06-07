// Run from /app/apps/workers inside the container
const path = require("path");

// better-sqlite3 path from the workers' node_modules
const BetterSqlite3 = require(
  path.join(process.cwd(), "node_modules/.pnpm/better-sqlite3@11.3.0/node_modules/better-sqlite3")
);

const db = new BetterSqlite3("/data/karakeep.db");

// Check queue tables
const qTables = db.prepare("SELECT name FROM sqlite_master WHERE type=? AND name LIKE ?").all("table", "%queue%");
console.log("Queue tables:", qTables.map(t => t.name).join(", "));

// Show queue schema if exists
if (qTables.length > 0) {
  const s = db.prepare("SELECT sql FROM sqlite_master WHERE name=?").get(qTables[0].name);
  console.log("Queue schema:", s ? s.sql.substring(0, 600) : "none");
}

// Count missing-image GitHub bookmarks
const cnt = db.prepare("SELECT COUNT(*) as c FROM bookmarkLinks bl INNER JOIN githubProjects gp ON gp.bookmark_id=bl.id WHERE bl.image_asset_id IS NULL AND bl.image_url IS NULL").get();
console.log("GitHub bookmarks missing images:", cnt.c);

// Get sample IDs
const samples = db.prepare("SELECT bl.id FROM bookmarkLinks bl INNER JOIN githubProjects gp ON gp.bookmark_id=bl.id WHERE bl.image_asset_id IS NULL AND bl.image_url IS NULL LIMIT 3").all();
console.log("Samples:", samples.map(s => s.id).join(", "));

db.close();
