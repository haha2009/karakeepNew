#!/usr/bin/env bash
# tools/loop-sync.sh — Detect drift between STATE.md and LOOP.md
#
# Adapted from loop-engineering (cobusgreyling/loop-engineering)
# Usage: bash tools/loop-sync.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${SCRIPT_DIR}/STATE.md"
LOOP_FILE="${SCRIPT_DIR}/LOOP.md"

echo "═══════════════════════════════════════════"
echo "  Loop Sync Report"
echo "═══════════════════════════════════════════"
echo ""

if [[ ! -f "$STATE_FILE" ]]; then
  echo "❌ STATE.md not found"
  exit 1
fi

if [[ ! -f "$LOOP_FILE" ]]; then
  echo "❌ LOOP.md not found"
  exit 1
fi

SCORE=100
ISSUES=0

# ── Check 1: LOOP.md references STATE.md ─────────────────────────────────
if grep -q "STATE.md" "$LOOP_FILE" 2>/dev/null; then
  echo "  ✅ LOOP.md references STATE.md"
else
  echo "  ⚠️  LOOP.md does not reference STATE.md"
  SCORE=$((SCORE - 10))
  ISSUES=$((ISSUES + 1))
fi

# ── Check 2: Last run timestamp freshness ─────────────────────────────────
LAST_RUN_LINE=$(grep -i "last run\|last updated" "$STATE_FILE" 2>/dev/null | head -1 || echo "")
if [[ -n "$LAST_RUN_LINE" ]]; then
  echo "  ✅ STATE.md has Last Run: ${LAST_RUN_LINE:0:50}"
else
  echo "  ⚠️  STATE.md missing Last Run timestamp"
  SCORE=$((SCORE - 10))
  ISSUES=$((ISSUES + 1))
fi

# ── Check 3: High Priority items have actions ─────────────────────────────
HIGH_PRI_COUNT=$(grep -c "^- \[" "$STATE_FILE" 2>/dev/null || echo "0")
if [[ $HIGH_PRI_COUNT -gt 0 ]]; then
  ITEMS_WITH_ACTIONS=$(grep -c "Loop action:" "$STATE_FILE" 2>/dev/null || echo "0")
  if [[ $ITEMS_WITH_ACTIONS -ge $HIGH_PRI_COUNT ]]; then
    echo "  ✅ All ${HIGH_PRI_COUNT} priority items have actions"
  else
    echo "  ⚠️  Only ${ITEMS_WITH_ACTIONS}/${HIGH_PRI_COUNT} items have actions"
    SCORE=$((SCORE - 5))
    ISSUES=$((ISSUES + 1))
  fi
else
  echo "  ℹ️  No priority items found (empty state)"
fi

# ── Check 4: Structural similarity ────────────────────────────────────────
STATE_LINES=$(wc -l < "$STATE_FILE")
LOOP_LINES=$(wc -l < "$LOOP_FILE")
if [[ $STATE_LINES -gt 10 && $LOOP_LINES -gt 10 ]]; then
  echo "  ✅ Both files have content (STATE: ${STATE_LINES} lines, LOOP: ${LOOP_LINES} lines)"
else
  echo "  ⚠️  One or both files seem sparse"
  SCORE=$((SCORE - 5))
  ISSUES=$((ISSUES + 1))
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "  Sync Score: ${SCORE}/100"
echo "═══════════════════════════════════════════"
echo ""

if [[ $SCORE -ge 80 ]]; then
  echo "  🟢 Healthy - loops and state are in sync"
elif [[ $SCORE -ge 50 ]]; then
  echo "  🟡 Warning - minor drift detected"
else
  echo "  🔴 Critical - significant drift, manual review needed"
fi

echo ""
echo "  ${ISSUES} issue(s) found"
echo ""

if [[ $ISSUES -gt 0 ]]; then
  echo "── Suggestions ──"
  echo "  1. Run: bash tools/loop-init.sh <pattern>"
  echo "  2. Update STATE.md after each loop run"
  echo "  3. Reference STATE.md from LOOP.md"
fi
echo ""
