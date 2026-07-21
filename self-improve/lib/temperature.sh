#!/usr/bin/env bash
# self-improve/lib/temperature.sh
# Simple pass/fail health check for the framework
# Returns: 0 = healthy, 1 = has issues

source "$(dirname "${BASH_SOURCE[0]}")/safety.sh"

FWK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Simple check: hook blocks dangerous + allows benign
check_health() {
  local hook="${FWK_DIR}/template/.claude/hooks/protect-framework.sh"
  local git_hook="${FWK_DIR}/template/.claude/hooks/protect-git.sh"
  local failures=0

  # Test 1: hook exists and is executable
  if [[ ! -x "$hook" ]]; then
    echo "FAIL: protect-framework.sh not executable"
    return 1
  fi

  # Test 2: hook blocks dangerous commands
  local dangerous_cmds=(
    'rm -rf .claude/' 'rm -rf .agents/' 'rm CLAUDE.md' 'rm AGENTS.md'
    'rm README.md' 'rm LOOP.md' 'rm STATE.md' 'rm .env'
  )
  for cmd in "${dangerous_cmds[@]}"; do
    local rc
    rc=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd" | bash "$hook" >/dev/null 2>&1; echo "$?")
    if [[ "$rc" -ne 2 ]]; then
      echo "FAIL: '$cmd' not blocked (rc=$rc)"
      failures=$((failures + 1))
    fi
  done

  # Test 3: hook allows benign commands
  local benign_cmds=(
    'ls' 'echo hello' 'cat .env' 'rm loop.md' 'rm CLAUDE.md.bak'
  )
  for cmd in "${benign_cmds[@]}"; do
    local rc
    rc=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd" | bash "$hook" >/dev/null 2>&1; echo "$?")
    if [[ "$rc" -ne 0 ]]; then
      echo "FAIL: '$cmd' falsely blocked (rc=$rc)"
      failures=$((failures + 1))
    fi
  done

  if [[ "$failures" -gt 0 ]]; then
    echo "RESULT: $failures failure(s)"
    return 1
  fi

  echo "RESULT: healthy"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  check_health
fi
