const Database = require("better-sqlite3");
const db = new Database("/data/karakeep.db");
const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all();
console.log("Tables:", tables.map(t => t.name).join(", "));
for (const t of tables.map(t => t.name)) {
  try {
    const c = db.prepare("SELECT COUNT(*) as cnt FROM " + t).get();
    console.log(t + ": " + c.cnt + " rows");
  } catch(e) {
    console.log(t + ": error - " + e.message.substring(0, 50));
  }
}
// Check bookmark_links specifically
try {
  const r = db.prepare(
    "SELECT COUNT(*) as total, SUM(CASE WHEN image_asset_id IS NOT NULL THEN 1 ELSE 0 END) as has_asset, SUM(CASE WHEN image_url IS NOT NULL THEN 1 ELSE 0 END) as has_url FROM bookmark_links"
  ).get();
  console.log("Bookmark images:", JSON.stringify(r));
} catch(e) {
  console.log("bookmark_links error:", e.message);
}
db.close();
