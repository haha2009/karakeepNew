#!/usr/bin/env bash
# tools/loop-worktree.sh — Manage isolated git worktrees per fix attempt
#
# Adapted from loop-engineering (cobusgreyling/loop-engineering)
# Integrates with existing worktree-manager.sh
#
# Usage:
#   bash tools/loop-worktree.sh create --run-id <id> --pattern <pattern>
#   bash tools/loop-worktree.sh mark --run-id <id> --status <rejected|approved|escalated>
#   bash tools/loop-worktree.sh cleanup --older-than 24h
#   bash tools/loop-worktree.sh list

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKTREE_BASE="${SCRIPT_DIR}/.worktrees"
MANIFEST_FILE="${WORKTREE_BASE}/.manifest.json"

mkdir -p "$WORKTREE_BASE"

# ── Create worktree ───────────────────────────────────────────────────────
create_worktree() {
  local run_id=""
  local pattern=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --run-id) run_id="$2"; shift 2 ;;
      --pattern) pattern="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  
  [[ -z "$run_id" ]] && { echo "Usage: create --run-id <id> [--pattern <pattern>]"; exit 1; }
  
  local branch_name="mcf-loop-$(date +%Y%m%d-%H%M%S)-${run_id}"
  local worktree_path="${WORKTREE_BASE}/${run_id}"
  
  # Create worktree with new branch from current HEAD
  git -C "$SCRIPT_DIR" worktree add "$worktree_path" -b "$branch_name" 2>/dev/null || {
    echo "❌ Failed to create worktree"
    exit 1
  }
  
  # Update manifest
  python3 - "$MANIFEST_FILE" "$run_id" "$pattern" "$branch_name" "$worktree_path" << 'PYEOF'
import json, sys, time

manifest_file, run_id, pattern, branch, path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

try:
    with open(manifest_file) as f:
        manifest = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    manifest = {"worktrees": []}

manifest["worktrees"].append({
    "run_id": run_id,
    "pattern": pattern,
    "branch": branch,
    "path": path,
    "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "status": "active"
})

with open(manifest_file, "w") as f:
    json.dump(manifest, f, indent=2)

print(f"✅ Worktree created: ${path}")
print(f"   Branch: ${branch}")
PYEOF
}

# ── Mark worktree status ─────────────────────────────────────────────────
mark_worktree() {
  local run_id=""
  local status=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --run-id) run_id="$2"; shift 2 ;;
      --status) status="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  
  [[ -z "$run_id" || -z "$status" ]] && { echo "Usage: mark --run-id <id> --status <rejected|approved|escalated>"; exit 1; }
  
  python3 - "$MANIFEST_FILE" "$run_id" "$status" << 'PYEOF'
import json, sys, time

manifest_file, run_id, status = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(manifest_file) as f:
        manifest = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print("❌ Manifest not found")
    sys.exit(1)

found = False
for wt in manifest.get("worktrees", []):
    if wt.get("run_id") == run_id:
        wt["status"] = status
        wt["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        found = True
        break

if found:
    with open(manifest_file, "w") as f:
        json.dump(manifest, f, indent=2)
    print(f"✅ Worktree ${run_id}: ${status}")
else:
    print(f"❌ Worktree not found: ${run_id}")
    sys.exit(1)
PYEOF
}

# ── Cleanup old worktrees ─────────────────────────────────────────────────
cleanup_worktrees() {
  local older_than="${1:-24h}"
  
  python3 - "$MANIFEST_FILE" "$older_than" << 'PYEOF'
import json, sys, os, shutil, time
from datetime import datetime, timedelta

manifest_file, older_than = sys.argv[1], sys.argv[2]

try:
    with open(manifest_file) as f:
        manifest = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print("No manifest found")
    sys.exit(0)

# Parse older_than
if older_than.endswith("h"):
    hours = int(older_than[:-1])
elif older_than.endswith("d"):
    hours = int(older_than[:-1]) * 24
else:
    hours = 24

cutoff = datetime.utcnow() - timedelta(hours=hours)
to_remove = []
remaining = []

for wt in manifest.get("worktrees", []):
    created = wt.get("created_at", "")
    try:
        created_dt = datetime.fromisoformat(created.replace("Z", "+00:00").replace("+00:00", ""))
        if created_dt < cutoff and wt.get("status") in ["rejected", "escalated"]:
            to_remove.append(wt)
        else:
            remaining.append(wt)
    except ValueError:
        remaining.append(wt)

# Remove worktree directories
for wt in to_remove:
    path = wt.get("path", "")
    if os.path.exists(path):
        shutil.rmtree(path)
        print(f"🗑️  Removed: {wt.get('run_id', '?')}")

manifest["worktrees"] = remaining
with open(manifest_file, "w") as f:
    json.dump(manifest, f, indent=2)

print(f"✅ Cleaned up {len(to_remove)} worktrees")
PYEOF
}

# ── List worktrees ────────────────────────────────────────────────────────
list_worktrees() {
  python3 - "$MANIFEST_FILE" << 'PYEOF'
import json, sys

manifest_file = sys.argv[1]

try:
    with open(manifest_file) as f:
        manifest = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print("No worktrees found")
    sys.exit(0)

worktrees = manifest.get("worktrees", [])
if not worktrees:
    print("No worktrees found")
    sys.exit(0)

print(f"Active worktrees: {len(worktrees)}")
for wt in worktrees:
    status = wt.get("status", "?")
    emoji = "🟢" if status == "active" else "✅" if status == "approved" else "❌"
    print(f"  {emoji} {wt.get('run_id', '?')}: {status} ({wt.get('pattern', '?')})")
    print(f"     Path: {wt.get('path', '?')}")
PYEOF
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-list}" in
  create)     shift; create_worktree "$@" ;;
  mark)       shift; mark_worktree "$@" ;;
  cleanup)    shift; cleanup_worktrees "$1" ;;
  list)       list_worktrees ;;
  *)          echo "Usage: bash tools/loop-worktree.sh {create|mark|cleanup|list}" ;;
esac
