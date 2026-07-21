#!/usr/bin/env bash
# self-improve/lib/safety.sh
# SAFETY_ZONE + INVARIANT definition for self-improve
#
# Design: WHITELIST editable surface + INVARIANT verification
# - Files NOT in safety_files/safety_paths are EDITABLE
# - Every merge must pass verify_invariant() (core protections intact)
# - held-in test covers ALL bypass vectors (not just the sacred one)

# Files NEVER modified (truly untouchable)
SAFETY_FILES=(
  "LICENSE"
)

# Paths NEVER touched (external open-source projects, user workspaces)
SAFETY_PATHS=(
  "node_modules/"
  ".git/"
  "work/"
  "test/"
  "experiments/"
  "skills/"                # mattpocock external skills
  ".agents/skills/"        # installed global skills
)

# INVARIANT: these protections must hold after EVERY merge
# We verify by running the commands through the hook and checking exit=2
INVARIANT_CMDS=(
  'rm -rf .claude/'        # Sacred: config dir
  'rm -rf .agents/'        # Sacred: agents dir  
  'rm CLAUDE.md'           # Core doc
  'rm AGENTS.md'           # Core doc
  'rm -rf .claude/skills'  # skills dir
  'git push --force'       # git safety
  'git reset --hard'       # git safety
  'git branch -D feature'  # git safety
)

# Check if a file path is in SAFETY_ZONE
# Returns 0 (true) if file is SAFE (must NOT be modified)
is_safety_file() {
  local filepath="$1"
  for safe in "${SAFETY_FILES[@]}"; do
    [[ "$filepath" == "$safe" || "$filepath" == "./$safe" ]] && return 0
  done
  for path in "${SAFETY_PATHS[@]}"; do
    [[ "$filepath" == "$path"* || "$filepath" == "./$path"* ]] && return 0
  done
  return 1
}

# Verify ALL invariants hold (core protections intact after change)
verify_invariant() {
  local framework_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
  local hook="${framework_dir}/template/.claude/hooks/protect-framework.sh"
  local git_hook="${framework_dir}/template/.claude/hooks/protect-git.sh"
  [[ -f "$hook" ]] || { echo "INVARIANT_FAIL: framework hook missing"; return 1; }
  
  local cmd out
  for cmd in "${INVARIANT_CMDS[@]}"; do
    if [[ "$cmd" == git* ]]; then
      [[ -f "$git_hook" ]] || continue
      out=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd" | bash "$git_hook" 2>/dev/null; echo "exit=$?")
    else
      out=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd" | bash "$hook" 2>/dev/null; echo "exit=$?")
    fi
    if ! echo "$out" | grep -q "exit=2"; then
      echo "INVARIANT_FAIL: '$cmd' not blocked"
      return 1
    fi
  done
  echo "INVARIANT_OK"
  return 0
}

# Source guard: prevent double-sourcing
[[ -n "${_SAFETY_SH_SOURCED:-}" ]] && return 0
_SAFETY_SH_SOURCED=1
