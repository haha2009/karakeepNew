#!/usr/bin/env bash
# self-improve/lib/self-test.sh
# Framework self-test — catches its own bugs before shipping
#
# Reference: Bot audit "Loop can't self-repair" + my verification
# B1-B4 were syntax errors the framework couldn't detect — this script fixes that

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FWK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE_DIR="${FWK_DIR}/template"

PASS=0
FAIL=0

# ── Colors ─────────────────────────────────────────────────────────────────
red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

# ── Test: bash syntax check all .sh files ──────────────────────────────────
test_bash_syntax() {
  echo "── 1/5: Bash syntax check ──"
  local files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$FWK_DIR" -name "*.sh" -not -path "*/.git/*" -not -path "*/work/*" -not -path "*/.scratch/*" -print0)
  
  for f in "${files[@]}"; do
    if bash -n "$f" 2>/dev/null; then
      PASS=$((PASS + 1))
    else
      red "FAIL: $f"
      bash -n "$f" 2>&1 | head -3 | sed 's/^/      /'
      FAIL=$((FAIL + 1))
    fi
  done
  echo ""
}

# ── Test: Python syntax check all .py files ────────────────────────────────
test_python_syntax() {
  echo "── 2/5: Python syntax check ──"
  local files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$FWK_DIR" -name "*.py" -not -path "*/.git/*" -print0)
  
  if [[ ${#files[@]} -eq 0 ]]; then
    yellow "  (no .py files found)"
    echo ""
    return
  fi
  
  for f in "${files[@]}"; do
    if python3 -c "import py_compile; py_compile.compile('$f', doraise=True)" 2>/dev/null; then
      PASS=$((PASS + 1))
    else
      red "FAIL: $f"
      python3 -c "import py_compile; py_compile.compile('$f', doraise=True)" 2>&1 | head -3 | sed 's/^/      /'
      FAIL=$((FAIL + 1))
    fi
  done
  echo ""
}

# ── Test: All sourced libraries exist ──────────────────────────────────────
test_sourced_libraries() {
  echo "── 3/5: Sourced libraries exist ──"
  local libs=(
    "self-improve/lib/safety.sh"
    "self-improve/lib/loop-guard.sh"
    "self-improve/lib/reflection.sh"
    "self-improve/lib/recovery.sh"
    "self-improve/lib/human-loop.sh"
    "self-improve/lib/orchestration.sh"
    "self-improve/lib/mcp-manager.sh"
    "self-improve/lib/rag.sh"
    "self-improve/lib/evaluation.sh"
    "self-improve/lib/prioritization.sh"
    "self-improve/lib/llm-provider.sh"
    "self-improve/lib/telemetry-loop.sh"
  )
  
  for lib in "${libs[@]}"; do
    if [[ -f "$FWK_DIR/$lib" ]]; then
      PASS=$((PASS + 1))
    else
      red "FAIL: $lib not found"
      FAIL=$((FAIL + 1))
    fi
  done
  echo ""
}

# ── Test: Required commands available ─────────────────────────────────────
test_required_commands() {
  echo "── 4/5: Required commands available ──"
  local cmds=(bash git python3 curl jq)
  
  for cmd in "${cmds[@]}"; do
    if command -v "$cmd" &>/dev/null; then
      PASS=$((PASS + 1))
    else
      if [[ "$cmd" == "jq" ]]; then
        yellow "WARN: $cmd not found (optional, fallback available)"
      else
        red "FAIL: $cmd not found (required)"
        FAIL=$((FAIL + 1))
      fi
    fi
  done
  echo ""
}

# ── Test: Hook files are valid ─────────────────────────────────────────────
test_hook_files() {
  echo "── 5/5: Hook files valid ──"
  local hooks=(
    ".claude/hooks/protect-framework.sh"
    ".claude/hooks/protect-git.sh"
    ".claude/hooks/session-start.sh"
    ".claude/settings.json"
  )
  
  for hook in "${hooks[@]}"; do
    local filepath="$FWK_DIR/$hook"
    if [[ ! -f "$filepath" ]]; then
      # Try template
      filepath="$TEMPLATE_DIR/$hook"
    fi
    
    if [[ -f "$filepath" ]]; then
      if [[ "$hook" == *.json ]]; then
        if python3 -c "import json; json.load(open('$filepath'))" 2>/dev/null; then
          PASS=$((PASS + 1))
        else
          red "FAIL: $hook invalid JSON"
          FAIL=$((FAIL + 1))
        fi
      else
        if bash -n "$filepath" 2>/dev/null; then
          PASS=$((PASS + 1))
        else
          red "FAIL: $hook syntax error"
          FAIL=$((FAIL + 1))
        fi
      fi
    else
      yellow "WARN: $hook not found"
    fi
  done
  echo ""
}

# ── Main ───────────────────────────────────────────────────────────────────
main() {
  echo "═══════════════════════════════════════════"
  echo "  MCF Self-Test"
  echo "═══════════════════════════════════════════"
  echo ""
  
  test_bash_syntax
  test_python_syntax
  test_sourced_libraries
  test_required_commands
  test_hook_files
  
  echo "═══════════════════════════════════════════"
  if [[ "$FAIL" -eq 0 ]]; then
    green "  ALL PASSED (${PASS} tests)"
    echo "═══════════════════════════════════════════"
    return 0
  else
    red "  ${FAIL} FAILED, ${PASS} passed"
    echo "═══════════════════════════════════════════"
    return 1
  fi
}

main "$@"
