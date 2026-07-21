#!/usr/bin/env bash
# self-improve/lib/verify.sh
# Independent verifier - checks that hook protection still works
# This is the "checker" that validates the "maker" (hook rules) hasn't regressed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FWK_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${FWK_DIR}/template/.claude/hooks/protect-framework.sh"
GIT_HOOK="${FWK_DIR}/template/.claude/hooks/protect-git.sh"

PASS=0
FAIL=0

check() {
  local desc="$1" cmd="$2" expect="$3"
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd" | bash "$HOOK" >/dev/null 2>&1
  local rc=$?
  if [[ "$rc" -eq "$expect" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: '$desc' cmd=[$cmd] expected=$expect got=$rc"
    FAIL=$((FAIL + 1))
  fi
}

check_git() {
  local desc="$1" cmd="$2" expect="$3"
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd" | bash "$GIT_HOOK" >/dev/null 2>&1
  local rc=$?
  if [[ "$rc" -eq "$expect" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: '$desc' cmd=[$cmd] expected=$expect got=$rc"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Hook Verification ==="

# Framework hook: must block
check "rm -rf .claude/" "rm -rf .claude/" 2
check "rm CLAUDE.md" "rm CLAUDE.md" 2
check "rm AGENTS.md" "rm AGENTS.md" 2
check "rm README.md" "rm README.md" 2
check "rm LOOP.md" "rm LOOP.md" 2
check "rm STATE.md" "rm STATE.md" 2
check "rm gate.yaml" "rm gate.yaml" 2
check "rm .env" "rm .env" 2

# Framework hook: must allow
check "rm loop.md" "rm loop.md" 0
check "rm state.md" "rm state.md" 0
check "rm CLAUDE.md.bak" "rm CLAUDE.md.bak" 0
check "rm MY.CLAUDE.md" "rm MY.CLAUDE.md" 0
check "cat .env" "cat .env" 0
check "cat CLAUDE.md" "cat CLAUDE.md" 0
check "ls .claude/" "ls .claude/" 0

# Git hook: must block
check_git "git push --force" "git push --force" 2
check_git "git reset --hard" "git reset --hard" 2
check_git "git branch -D feature" "git branch -D feature" 2

# Git hook: must allow
check_git "git status" "git status" 0
check_git "git push origin main" "git push origin main" 0
check_git "git log" "git log" 0

echo ""
echo "Result: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]] && echo "✅ Hook protection verified" || echo "❌ Hook regression detected"
exit "$FAIL"
