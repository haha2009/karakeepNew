#!/usr/bin/env bash
# audit-skill.sh — Pre-installation audit for skills
# Scans SKILL.md files for prompt injection vectors before allowing install.
#
# Reference: 0xCodez "Skills as injection vectors. A loop that auto-installs skills
#             inherits every prompt injection hiding in their descriptions."
# Reference: 520 of 17,022 audited skills leak credentials (0xCodez metric)
#
# Usage: audit-skill.sh <path-to-skill-dir-or-SKILL.md>
# Exit: 0 = clean, 1 = warnings, 2 = blocking issues found

set -uo pipefail

TARGET="${1:-}"
[[ -z "$TARGET" ]] && { echo "Usage: audit-skill.sh <skill-dir-or-SKILL.md>"; exit 1; }

# Resolve to SKILL.md
if [[ -d "$TARGET" ]]; then
  TARGET="${TARGET}/SKILL.md"
  [[ ! -f "$TARGET" ]] && TARGET="${TARGET%/}/SKILL.md"
fi
[[ ! -f "$TARGET" ]] && { echo "❌ SKILL.md not found: $TARGET"; exit 2; }

ISSUES=0
WARNINGS=0

echo "═══ Skill Audit: $TARGET ═══"
echo ""

# ── 1. Frontmatter integrity ────────────────────────────────────────────────
echo "── 1/6: Frontmatter Check ──"
if ! head -1 "$TARGET" | grep -q '^---'; then
  echo "   ⚠️  No YAML frontmatter found (expected --- delimiter)"
  WARNINGS=$((WARNINGS + 1))
else
  echo "   ✅ Frontmatter present"
fi

# Check for required fields
for field in "name" "description"; do
  if ! grep -qE "^${field}:" "$TARGET"; then
    echo "   ⚠️  Missing frontmatter field: ${field}"
    WARNINGS=$((WARNINGS + 1))
  fi
done
echo ""

# ── 2. Prompt injection patterns ────────────────────────────────────────────
echo "── 2/6: Injection Pattern Scan ──"

# Patterns that indicate potential prompt injection
INJECTION_PATTERNS=(
  # Directives that override system instructions
  "ignore (all |any |previous |above )"
  "disregard (your |all |previous |instructions)"
  "forget (your |all |previous |instructions)"
  "you are now"
  "new instructions?:"
  "override (your |all |previous |system )"
  "system prompt:"
  "developer mode"
  "DAN"
  "jailbreak"
  # Hidden instructions (zero-width chars, invisible text)
  # Note: can't easily detect zero-width in bash, flag suspicious unicode
  # Credential harvesting
  "send (this |the |data |tokens |keys )to"
  "exfiltrate"
  "POST to http"
  "curl.*\|.*bash"
  "wget.*\|.*sh"
  # Obfuscation
  "base64.*decode"
  "eval\("
  "exec\("
  "os\.system"
  "subprocess"
)

for pattern in "${INJECTION_PATTERNS[@]}"; do
  if grep -qiE "$pattern" "$TARGET" 2>/dev/null; then
    echo "   🚫 BLOCK: Potential injection pattern: /$pattern/"
    # Show the matching line
    grep -niE "$pattern" "$TARGET" | head -3 | while IFS= read -r line; do
      echo "      → $line"
    done
    ISSUES=$((ISSUES + 1))
  fi
done

if [[ "$ISSUES" -eq 0 ]]; then
  echo "   ✅ No injection patterns detected"
fi
echo ""

# ── 3. External references ──────────────────────────────────────────────────
echo "── 3/6: External Reference Check ──"
URL_COUNT=0
while IFS= read -r url; do
  URL_COUNT=$((URL_COUNT + 1))
  # Flag non-official sources
  if echo "$url" | grep -qvE '(github\.com|anthropic\.com|docs\.anthropic\.com|modelcontextprotocol\.io)'; then
    echo "   ⚠️  External URL: $url"
  fi
done < <(grep -oE 'https?://[^ "]*' "$TARGET" 2>/dev/null)
echo ""

# ── 4. Scope analysis ──────────────────────────────────────────────────────
echo "── 4/6: Scope Analysis ──"
# Does the skill request broad permissions?
if grep -qiE '(file system|root access|admin|sudo|all files|full access)' "$TARGET"; then
  echo "   ⚠️  Skill requests broad system access"
  WARNINGS=$((WARNINGS + 1))
fi
# Does it try to modify system files?
if grep -qiE '(\.bashrc|\.zshrc|\.profile|/etc/|/usr/)' "$TARGET"; then
  echo "   🚫 BLOCK: Skill references system file paths"
  ISSUES=$((ISSUES + 1))
fi
echo ""

# ── 5. Credential patterns ──────────────────────────────────────────────────
echo "── 5/6: Credential Leak Check ──"
CRED_PATTERNS=(
  'API[_-]?KEY[:=][[:space:]]*["'"'"'][a-zA-Z0-9_\-]{16,}]'
  'SECRET[_-]?KEY[:=][[:space:]]*["'"'"'][a-zA-Z0-9_\-]{16,}]'
  'PASSWORD[:=][[:space:]]*["'"'"'][^"'"'"']{8,}]'
  'TOKEN[:=][[:space:]]*["'"'"'][a-zA-Z0-9_\-]{16,}]'
  'PRIVATE[_-]?KEY'
  'BEGIN (RSA |DSA |EC |OPENSSH )?PRIVATE KEY'
)

for pattern in "${CRED_PATTERNS[@]}"; do
  if grep -qiE "$pattern" "$TARGET" 2>/dev/null; then
    echo "   🚫 BLOCK: Potential credential in skill content"
    ISSUES=$((ISSUES + 1))
  fi
done

if [[ "$ISSUES" -eq 0 ]]; then
  echo "   ✅ No credentials detected in content"
fi
echo ""

# ── 6. Size and complexity ──────────────────────────────────────────────────
echo "── 6/6: Size Check ──"
LINE_COUNT=$(wc -l < "$TARGET")
if [[ "$LINE_COUNT" -gt 500 ]]; then
  echo "   ⚠️  Large skill file: ${LINE_COUNT} lines (consider splitting)"
  WARNINGS=$((WARNINGS + 1))
else
  echo "   ✅ Size: ${LINE_COUNT} lines"
fi
echo ""

# ── Verdict ─────────────────────────────────────────────────────────────────
echo "═══ Verdict ═══"
if [[ "$ISSUES" -gt 0 ]]; then
  echo "🚫 REJECTED: ${ISSUES} blocking issue(s), ${WARNINGS} warning(s)"
  echo "   Action: Do not install. Review the skill source manually."
  exit 2
elif [[ "$WARNINGS" -gt 0 ]]; then
  echo "⚠️  CONDITIONAL: ${WARNINGS} warning(s)"
  echo "   Action: Review warnings before installing. Use --force to override."
  exit 1
else
  echo "✅ CLEAN: No issues found"
  echo "   Action: Safe to install"
  exit 0
fi
