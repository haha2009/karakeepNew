#!/usr/bin/env bash
# post-edit.sh — PostToolUse Hook
# Fires after Edit|Write: enforces policy floor (formatting, lint, secrets).
# Non-blocking on success, blocking only on critical findings.
#
# stdin: JSON { "tool_name": "Edit"|"Write", "tool_input": { "file_path": "..." }, "tool_output": { ... } }

set -uo pipefail

# Read stdin
INPUT=""
while IFS= read -r line || [ -n "$line" ]; do INPUT="$INPUT$line"; done

# Parse file_path
FILE_PATH=""
if command -v jq &>/dev/null; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_output.file_path // empty' 2>/dev/null)
else
  FILE_PATH=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

[[ -z "$FILE_PATH" ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

# Get project root (where .claude/ lives)
PROJECT_ROOT="$PWD"
while [[ "$PROJECT_ROOT" != "/" ]] && [[ ! -d "$PROJECT_ROOT/.claude" ]]; do
  PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done
[[ "$PROJECT_ROOT" == "/" ]] && exit 0

ISSUES=0

  # Check whitelist first (user-configurable bypass)
  BYPASS_FILE="${PROJECT_ROOT}/.claude/hook-bypass.json"
  if [[ -f "$BYPASS_FILE" ]] && command -v python3 >/dev/null 2>&1; then
    if python3 - "$FILE_PATH" "$BYPASS_FILE" 2>/dev/null << 'PYEOF'
import json, sys, re
filepath, bypass_file = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(bypass_file))
    if not data.get("enabled", True):
        sys.exit(1)
    for pattern in data.get("whitelisted_files", []):
        if re.search(pattern, filepath):
            sys.exit(0)
except Exception:
    pass
sys.exit(1)
PYEOF
    then
      exit 0
    fi
  fi

# ── 1. Secret leak scan ────────────────────────────────────────────────────
# Block if the edit introduced a potential secret
if grep -qE '(API_KEY|SECRET_KEY|PASSWORD|TOKEN|PRIVATE_KEY)[[:space:]]*[:=][[:space:]]*["'"'"'][a-zA-Z0-9_\-]{16,}' "$FILE_PATH" 2>/dev/null; then
  echo "    Pattern: API_KEY/SECRET_KEY/PASSWORD/TOKEN/PRIVATE_KEY assignment" >&2
  echo "    Action: Remove secret from code, use .env or secrets manager" >&2
  ISSUES=$((ISSUES + 1))
fi

# ── 2. Debug flag left behind ──────────────────────────────────────────────
if grep -qE '(debugger|console\.log|binding\.pry|byebug|pdb\.set_trace)[[:space:]]*[;:]?' "$FILE_PATH" 2>/dev/null; then
  # Check if it was pre-existing (not in this edit) — simplified: just warn
  echo "⚠️ PostEdit: Debug statement found in ${FILE_PATH}" >&2
  echo "    Remove before commit: debugger/console.log/binding.pry/etc." >&2
  # Warning only, not blocking
fi

# ── 3. TODO/FIXME without ticket reference ──────────────────────────────────
if grep -qE '(TODO|FIXME|XXX|HACK)[[:space:]]*:[[:space:]]*[A-Za-z]' "$FILE_PATH" 2>/dev/null; then
  if grep -qE '(TODO|FIXME|XXX|HACK)[[:space:]]*:[[:space:]]*[A-Za-z].*#\d+' "$FILE_PATH" 2>/dev/null; then
    : # Has ticket reference, OK
  else
    echo "⚠️ PostEdit: TODO/FIXME without ticket reference in ${FILE_PATH}" >&2
    echo "    Format: TODO(#123): description" >&2
  fi
fi

# ── 4. Auto-format (if formatter available for this extension) ──────────────
EXT="${FILE_PATH##*.}"
case "$EXT" in
  ts|tsx|js|jsx|mjs|cjs)
    if command -v npx &>/dev/null && [[ -f "$PROJECT_ROOT/package.json" ]]; then
      if grep -q '"prettier"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
        npx prettier --write "$FILE_PATH" 2>/dev/null || true
      elif grep -q '"eslint"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
        npx eslint --fix "$FILE_PATH" 2>/dev/null || true
      fi
    fi
    ;;
  py)
    if command -v ruff &>/dev/null; then
      ruff format "$FILE_PATH" 2>/dev/null || true
    elif command -v black &>/dev/null; then
      black "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
  kt|kts)
    if command -v ktlint &>/dev/null; then
      ktlint --format "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
  go)
    if command -v gofmt &>/dev/null; then
      gofmt -w "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
  rs)
    if command -v rustfmt &>/dev/null; then
      rustfmt "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
  json|md|yaml|yml)
    if command -v npx &>/dev/null && grep -q '"prettier"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
      npx prettier --write "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
esac

# ── 5. Line length warning (soft) ───────────────────────────────────────────
LONG_LINES=$(awk 'length > 120 { print NR": "substr($0,1,60)"..." }' "$FILE_PATH" 2>/dev/null | head -5)
if [[ -n "$LONG_LINES" ]]; then
  echo "⚠️ PostEdit: Lines exceeding 120 chars in ${FILE_PATH}:" >&2
  echo "$LONG_LINES" | while IFS= read -r line; do echo "    $line" >&2; done
fi

if [[ "$ISSUES" -gt 0 ]]; then
  echo "🚫 PostEdit: ${ISSUES} blocking issue(s) in ${FILE_PATH}" >&2
  exit 2
fi

exit 0
