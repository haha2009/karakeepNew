#!/usr/bin/env bash
# self-improve/lib/memory.sh
# Persistent memory for self-improve operations

source "$(dirname "${BASH_SOURCE[0]}")/safety.sh"

FWK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MEMORY_DIR="${FWK_DIR}/.memory"
HISTORY_FILE="${MEMORY_DIR}/self-improve-history.md"
PATTERNS_FILE="${MEMORY_DIR}/self-improve-patterns.md"

init_memory() {
  mkdir -p "$MEMORY_DIR"
  [[ -f "$HISTORY_FILE" ]] || echo "# Self-Improve History" > "$HISTORY_FILE"
  [[ -f "$PATTERNS_FILE" ]] || echo "# Self-Improve Patterns" > "$PATTERNS_FILE"
}

log_round() {
  local round_num="$1" temp_before="$2" temp_after="$3" weaknesses="$4" changes="$5" result="$6"
  init_memory
  printf '%s\n' \
    "## Round ${round_num} - $(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "- Temperature: ${temp_before} -> ${temp_after}" \
    "- Weaknesses Found: ${weaknesses}" \
    "- Changes Made: ${changes}" \
    "- Result: ${result}" \
    "" \
    >> "$HISTORY_FILE"
}

log_rejection() {
  local proposal="$1"
  local reason="$2"
  printf '%s\n' \
    "### Rejected Proposal" \
    "- Proposal: ${proposal}" \
    "- Reason: ${reason}" \
    "- Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "" \
    >> "$HISTORY_FILE"
}

log_temperature() {
  local temp="$1" trigger="$2" rounds="$3" outcome="$4"
  init_memory
  echo "| $(date -u +%Y-%m-%d) | ${temp} | ${trigger} | ${rounds} | ${outcome} |" >> "$PATTERNS_FILE"
}

record_failure_pattern() {
  local pattern="$1" context="$2"
  init_memory
  printf '%s\n' \
    "### Failure Pattern: ${pattern}" \
    "- Context: ${context}" \
    "- Recorded: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "" \
    >> "$PATTERNS_FILE"
}

record_success_pattern() {
  local pattern="$1" context="$2"
  init_memory
  printf '%s\n' \
    "### Success Pattern: ${pattern}" \
    "- Context: ${context}" \
    "- Recorded: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "" \
    >> "$PATTERNS_FILE"
}

was_previously_rejected() {
  local sig="$1"
  init_memory
  grep -qF "$sig" "$HISTORY_FILE" 2>/dev/null
}

get_recent_rounds() {
  local n="${1:-5}"
  init_memory
  grep -A 10 "^## Round" "$HISTORY_FILE" | tail -n "$((n * 10))"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    prune)
      shift
      prune_memory "${1:-}"
      ;;
    auto-prune)
      shift
      auto_prune_check "${1:-}"
      ;;
    *)
      init_memory
      echo "=== Self-Improve History ==="
      get_recent_rounds 3
      echo ""
      echo "Commands: prune [file] | auto-prune [file]"
      ;;
  esac
fi

# ── MEMORY Pruning ─────────────────────────────────────────────────────────
# Reference: ArchiveExplorer "The first mistake is treating memory as append-only.
#             Prune it every session, or it becomes the rot."
# Reference: 0xCodez "Context rot — accuracy collapses around 200K tokens"

MEMORY_INDEX_FILE="${MEMORY_DIR}/MEMORY.md"
PRUNE_MAX_LINES=200        # Keep under this many lines
PRUNE_MAX_AGE_DAYS=30      # Entries older than this get summarized
PRUNE_MIN_KEEP=50          # Never go below this many lines

prune_memory() {
  local file="${1:-$MEMORY_INDEX_FILE}"
  [[ ! -f "$file" ]] && return 0
  
  local line_count
  line_count=$(wc -l < "$file")
  
  # Under limit — nothing to do
  if [[ "$line_count" -le "$PRUNE_MAX_LINES" ]]; then
    echo "MEMORY_OK: ${line_count}/${PRUNE_MAX_LINES} lines"
    return 0
  fi
  
  python3 - "$file" "$PRUNE_MAX_LINES" "$PRUNE_MAX_AGE_DAYS" "$PRUNE_MIN_KEEP" << 'PYEOF'
import json, sys, os, re, time
from datetime import datetime, timedelta

file_path, max_lines, max_age_days, min_keep = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])

with open(file_path, 'r') as f:
    content = f.read()

lines = content.split('\n')
original_count = len(lines)

# Strategy 1: Remove old detailed entries (older than max_age_days)
# Keep only their headers, collapse body
cutoff = datetime.utcnow() - timedelta(days=max_age_days)
cutoff_str = cutoff.strftime("%Y-%m-%d")

pruned = []
collapsed_count = 0
in_old_section = False

for line in lines:
    # Detect date patterns like "## 2026-07-15" or "### 2026-07"
    date_match = re.match(r'^#{2,3}\s+(\d{4}-\d{2}(?:-\d{2})?)', line)
    if date_match:
        date_str = date_match.group(1)
        try:
            if len(date_str) == 10:  # full date
                entry_date = datetime.strptime(date_str, "%Y-%m-%d")
                in_old_section = entry_date < cutoff
            else:  # month only, keep
                in_old_section = False
        except ValueError:
            in_old_section = False
    
    if in_old_section and not line.startswith('#'):
        # Skip detail lines in old sections (collapse)
        collapsed_count += 1
        continue
    
    pruned.append(line)

# Strategy 2: If still over limit, keep most recent sections + header
if len(pruned) > max_lines:
    # Always keep the first 20 lines (header/index)
    header = pruned[:20]
    rest = pruned[20:]
    # Keep the most recent entries that fit
    keep_count = max(min_keep - 20, max_lines - 20)
    pruned = header + rest[-keep_count:]
    collapsed_count += len(rest) - keep_count

with open(file_path, 'w') as f:
    f.write('\n'.join(pruned))

print(f"PRUNED: {original_count} → {len(pruned)} lines (collapsed {collapsed_count})")
PYEOF
}

# Auto-prune check (call at start of each session/run)
auto_prune_check() {
  local file="${1:-$MEMORY_INDEX_FILE}"
  [[ ! -f "$file" ]] && return 0
  
  local line_count
  line_count=$(wc -l < "$file")
  
  if [[ "$line_count" -gt "$PRUNE_MAX_LINES" ]]; then
    echo "⚠️  MEMORY.md over limit (${line_count}/${PRUNE_MAX_LINES} lines). Pruning..."
    prune_memory "$file"
  fi
}
