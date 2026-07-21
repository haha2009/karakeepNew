#!/usr/bin/env bash
# comprehension-debt.sh — Track code shipped but not understood
# Marks diffs that haven't been read by a human.
#
# Reference: 0xCodez "Comprehension debt. The faster the loop ships code you didn't
#             write, the larger the distance between what the repository contains
#             and what you understand."
#
# Usage:
#   comprehension-debt.sh mark <file>     # Mark a file as unread
#   comprehension-debt.sh read <file>     # Mark a file as read
#   comprehension-debt.sh check           # Show all unread files
#   comprehension-debt.sh scan            # Auto-scan git diff for unread files
#   comprehension-debt.sh report          # Full debt report

set -uo pipefail

FWK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEBT_FILE="${FWK_DIR}/.memory/.comprehension-debt.json"

# ── State management ────────────────────────────────────────────────────────
init_debt() {
  if [[ ! -f "$DEBT_FILE" ]]; then
    echo '{"unread":[],"read":[],"total_debt":0}' > "$DEBT_FILE"
  fi
}

mark_unread() {
  local file="$1"
  local reason="${2:-auto-detected}"
  init_debt
  
  python3 - "$DEBT_FILE" "$file" "$reason" << 'PYEOF'
import json, sys, time, os
debt_file, file_path, reason = sys.argv[1], sys.argv[2], sys.argv[3]
debt = json.load(open(debt_file))

# Check if already tracked
existing = next((item for item in debt["unread"] if item["file"] == file_path), None)
if not existing:
    debt["unread"].append({
        "file": file_path,
        "marked_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "reason": reason,
        "status": "unread"
    })
    debt["total_debt"] = len(debt["unread"])

json.dump(debt, open(debt_file, "w"), indent=2)
print(f"MARKED_UNREAD: {file_path}")
PYEOF
}

mark_read() {
  local file="$1"
  init_debt
  
  python3 - "$DEBT_FILE" "$file" << 'PYEOF'
import json, sys, time
debt_file, file_path = sys.argv[1], sys.argv[2]
debt = json.load(open(debt_file))

# Move from unread to read
for item in debt["unread"]:
    if item["file"] == file_path:
        item["read_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        item["status"] = "read"
        debt["read"].append(item)
        break

debt["unread"] = [item for item in debt["unread"] if item["file"] != file_path]
debt["total_debt"] = len(debt["unread"])

json.dump(debt, open(debt_file, "w"), indent=2)
print(f"MARKED_READ: {file_path}")
PYEOF
}

# ── Check ───────────────────────────────────────────────────────────────────
check_debt() {
  init_debt
  python3 - "$DEBT_FILE" << 'PYEOF'
import json, sys, os
debt = json.load(open(sys.argv[1]))
unread = debt.get("unread", [])

if not unread:
    print("✅ No comprehension debt. All changes reviewed.")
    sys.exit(0)

print(f"⚠️  Comprehension Debt: {len(unread)} unread file(s)")
print("")
for item in unread:
    print(f"  📄 {item['file']}")
    print(f"     Marked: {item.get('marked_at', 'unknown')[:10]}")
    print(f"     Reason: {item.get('reason', 'unknown')}")
    print("")
PYEOF
}

# ── Scan ────────────────────────────────────────────────────────────────────
scan_diff() {
  echo "Scanning recent changes for unread files..."
  
  # Get files changed in last commit that haven't been marked read
  git -C "$FWK_DIR" diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null | while IFS= read -r file; do
    # Skip framework config files (auto-managed)
    if echo "$file" | grep -qE '(\.memory/|\.loop-state|\.worktree-state|\.comprehension-debt|\.cb-state|\.drift-history|\.apply-fingerprints|vcr\.json|quality-snapshots\.md|self-improve-history\.md|self-improve-patterns\.md|analysis\.md|weaknesses\.json|verification\.json|proposals\.json|framework-telemetry\.jsonl)'; then
      continue
    fi
    mark_unread "$file" "auto-scanned from git"
  done
  
  echo "Scan complete. Run 'comprehension-debt.sh check' to see results."
}

# ── Report ──────────────────────────────────────────────────────────────────
report() {
  init_debt
  python3 - "$DEBT_FILE" << 'PYEOF'
import json, sys, os
from datetime import datetime
debt = json.load(open(sys.argv[1]))

unread = debt.get("unread", [])
read = debt.get("read", [])

print("═══ Comprehension Debt Report ═══")
print(f"")
print(f"Unread files: {len(unread)}")
print(f"Read files: {len(read)}")
print(f"")

if unread:
    print("⚠️  UNREAD (need human review):")
    for item in unread:
        marked = item.get("marked_at", "unknown")
        print(f"  📄 {item['file']}")
        print(f"     Since: {marked[:10]} | Reason: {item.get('reason', 'unknown')}")
    print("")

if read:
    print(f"✅ Recently read ({min(len(read), 5)} most recent):")
    for item in read[-5:]:
        read_at = item.get("read_at", "unknown")
        print(f"  📄 {item['file']} ({read_at[:10]})")
    print("")

if len(unread) > 5:
    print("🚨 HIGH DEBT WARNING: More than 5 unread files.")
    print("   Action: Review diffs before adding more changes.")
    print("   The day you debug a system no one has read costs more than the tokens ever did.")
elif len(unread) > 0:
    print("💡 Tip: Read the diffs. Comprehension debt compounds at interest.")
else:
    print("✅ All clear. Keep reviewing changes.")
PYEOF
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-check}" in
  mark)   shift; mark_unread "${1:-}" "${2:-manual}" ;;
  read)   shift; mark_read "${1:-}" ;;
  check)  check_debt ;;
  scan)   scan_diff ;;
  report) report ;;
  *)      echo "Usage: comprehension-debt.sh {mark <file>|read <file>|check|scan|report}" ;;
esac
