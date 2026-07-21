#!/usr/bin/env bash
# tools/loop-gate.sh — Mechanical enforcement of path denylist + auto-merge allowlist
#
# Adapted from loop-engineering (cobusgreyling/loop-engineering)
# Usage: bash tools/loop-gate.sh check --action auto-merge --paths <f1,f2,...>
#        bash tools/loop-gate.sh check --action push --paths <f1,f2,...>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_FILE="${SCRIPT_DIR}/gate.yaml"

ACTION=""
PATHS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action) ACTION="$2"; shift 2 ;;
    --paths) PATHS="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$ACTION" ]]; then
  echo "Usage: bash tools/loop-gate.sh check --action <auto-merge|push> --paths <f1,f2,...>"
  exit 1
fi

# ── Read denylist from gate.yaml ──────────────────────────────────────────
get_denylist() {
  if [[ ! -f "$GATE_FILE" ]]; then
    echo ""
    return
  fi
  python3 - "$GATE_FILE" << 'PYEOF'
import yaml, sys
with open(sys.argv[1]) as f:
    config = yaml.safe_load(f)
invariant = config.get("invariant", {})
must_block = invariant.get("must_block", [])
# Extract command patterns
import re
patterns = []
for cmd in must_block:
    # Extract the command part after the comment
    match = re.search(r'"([^"]*)"', cmd)
    if match:
        patterns.append(match.group(1))
print(",".join(patterns))
PYEOF
}

# ── Check paths against rules ─────────────────────────────────────────────
check_paths() {
  local action="$1"
  local paths="$2"
  local denylist
  denylist=$(get_denylist)
  
  local blocked=0
  local warnings=0
  
  IFS=',' read -ra PATH_ARRAY <<< "$paths"
  IFS=',' read -ra DENY_ARRAY <<< "$denylist"
  
  for path in "${PATH_ARRAY[@]}"; do
    path=$(echo "$path" | xargs)  # trim
    
    # Check denylist
    for deny_pattern in "${DENY_ARRAY[@]}"; do
      deny_pattern=$(echo "$deny_pattern" | xargs)
      if [[ -n "$deny_pattern" ]] && grep -q "$deny_pattern" <<< "$path" 2>/dev/null; then
        echo "  ❌ BLOCKED: '${path}' matches denylist pattern '${deny_pattern}'"
        blocked=$((blocked + 1))
      fi
    done
    
    # Check for sensitive files
    if grep -qE '(\.env|keystore|\.jks|secrets|credentials)' <<< "$path" 2>/dev/null; then
      echo "  ⚠️  WARNING: '${path}' looks sensitive"
      warnings=$((warnings + 1))
    fi
  done
  
  echo ""
  if [[ $blocked -gt 0 ]]; then
    echo "  Result: BLOCKED (${blocked} violation(s))"
    return 2
  elif [[ $warnings -gt 0 ]]; then
    echo "  Result: ALLOWED WITH WARNINGS (${warnings} warning(s))"
    return 1
  else
    echo "  Result: ALLOWED"
    return 0
  fi
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-check}" in
  check) check_paths "$ACTION" "$PATHS" ;;
  *) echo "Usage: bash tools/loop-gate.sh check --action <auto-merge|push> --paths <f1,f2,...>" ;;
esac
