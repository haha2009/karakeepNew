#!/usr/bin/env bash
# quick-verify.sh — "Is your MCF framework working?"
# Read-only. Safe to run from any MCF-injected project root.
#
# Usage:
#   bash quick-verify.sh          # run checks
#   bash quick-verify.sh --quiet  # exit code only (0 = healthy)
set -uo pipefail

if [[ -t 1 ]] && command -v tput &>/dev/null && [[ "${COLOR:-1}" != "0" ]]; then
  R=$(tput setaf 1); G=$(tput setaf 2); Y=$(tput setaf 3); B=$(tput bold); N=$(tput sgr0)
else R=""; G=""; Y=""; B=""; N=""
fi

PASS=0; FAIL=0; WARN=0
ok()   { echo "  ${G}✓${N} $1"; PASS=$((PASS+1)); }
bad()  { echo "  ${R}✗${N} $1"; FAIL=$((FAIL+1)); }
warn() { echo "  ${Y}!${N} $1"; WARN=$((WARN+1)); }

json_val() {
  local json="$1" key="$2"
  if command -v jq &>/dev/null; then echo "$json" | jq -r "$key" 2>/dev/null
  else echo "$json" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"; fi
}

echo ""
echo "1️⃣  Hook Registration"
echo "─────────────────────"
SETTINGS=".claude/settings.json"
if [[ ! -f "$SETTINGS" ]]; then
  bad ".claude/settings.json — missing (framework not injected)"
else
  SETTINGS_JSON=$(cat "$SETTINGS")
  for hook_name in protect-framework.sh protect-git.sh session-start.sh; do
    if echo "$SETTINGS_JSON" | grep -q "$hook_name"; then ok "$hook_name — registered"
    else bad "$hook_name — MISSING"; fi
  done
fi

echo ""
echo "2️⃣  Hook Protection (behavioral)"
echo "─────────────────────────────────"
invoke_hook() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | bash "$2" 2>/dev/null; return $?; }

FRAMEWORK_HOOK=".claude/hooks/protect-framework.sh"
if [[ -f "$FRAMEWORK_HOOK" ]]; then
  for dangerous in "rm -rf .claude/" "rm CLAUDE.md" "rm .env" "npx skills add test/foo"; do
    invoke_hook "$dangerous" "$FRAMEWORK_HOOK"; rc=$?
    [[ "$rc" -eq 2 ]] && ok "BLOCK: '${dangerous}'" || bad "ALLOW (rc=$rc): '${dangerous}'"
  done
  for safe in "cat CLAUDE.md" "ls .claude/" "rm .env.local" "rm loop.md"; do
    invoke_hook "$safe" "$FRAMEWORK_HOOK"; rc=$?
    [[ "$rc" -eq 0 ]] && ok "ALLOW: '${safe}'" || bad "WRONGLY BLOCKED (rc=$rc): '${safe}'"
  done
else
  bad "protect-framework.sh — FILE MISSING"
fi

GIT_HOOK=".claude/hooks/protect-git.sh"
if [[ -f "$GIT_HOOK" ]]; then
  for dangerous in "git push --force" "git reset --hard" "git branch -D feature"; do
    invoke_hook "$dangerous" "$GIT_HOOK"; rc=$?
    [[ "$rc" -eq 2 ]] && ok "BLOCK: '${dangerous}'" || bad "ALLOW (rc=$rc): '${dangerous}'"
  done
  for safe in "git status" "git log" "git push origin main"; do
    invoke_hook "$safe" "$GIT_HOOK"; rc=$?
    [[ "$rc" -eq 0 ]] && ok "ALLOW: '${safe}'" || bad "WRONGLY BLOCKED (rc=$rc): '${safe}'"
  done
else
  bad "protect-git.sh — FILE MISSING"
fi

echo ""
echo "3️⃣  Skills Installed"
echo "────────────────────"
TOTAL_SKILLS=0
for sdir in ".claude/skills" ".agents/skills"; do
  [[ -d "$sdir" ]] && while IFS= read -r skill_md; do TOTAL_SKILLS=$((TOTAL_SKILLS + 1)); done < <(find "$sdir" -maxdepth 3 -name 'SKILL.md' 2>/dev/null)
done
[[ "$TOTAL_SKILLS" -gt 0 ]] && ok "${TOTAL_SKILLS} skills installed" || warn "0 skills installed"

echo ""
echo "4️⃣  Framework Version"
echo "────────────────────"
VERSION_FILE=".framework-version"
if [[ ! -f "$VERSION_FILE" ]]; then
  bad ".framework-version — FILE MISSING"
else
  CURRENT_VER=$(cat "$VERSION_FILE")
  echo "  Local version: ${B}${CURRENT_VER}${N}"
  LATEST_VER=$(curl -sL --connect-timeout 3 --max-time 5 \
    "https://raw.githubusercontent.com/haha2009/my-claude-fwk/main/.framework-version" 2>/dev/null || echo "")
  if [[ -z "$LATEST_VER" ]]; then warn "Cannot reach GitHub (offline?)"
  elif [[ "$CURRENT_VER" == "$LATEST_VER" ]]; then ok "Up to date"
  else bad "Out of date: latest=${LATEST_VER}"; echo "  → Fix: bash update.sh"; fi
fi

echo ""
echo "════════════════════════════════════════"
echo ""
echo "Summary: ${G}${PASS} passed${N}  ${R}${FAIL} failed${N}  ${Y}${WARN} warnings${N}"
echo ""
[[ "$FAIL" -eq 0 ]] && echo "  ${G}${B}✅ Framework healthy.${N}" || echo "  ${R}${B}❌ Framework has issues.${N}"
exit "$FAIL"
