#!/usr/bin/env bash
# tools/loop-cost.sh — Estimate token cost for a loop pattern
#
# Adapted from loop-engineering (cobusgreyling/loop-engineering)
# Usage: bash tools/loop-cost.sh <pattern> [--level L1|L2|L3] [--cadence 1d|2h|15m]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATTERNS_DIR="${SCRIPT_DIR}/patterns"

PATTERN="${1:-}"
LEVEL="L1"
CADENCE="1d"

# Parse optional flags
shift 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --level) LEVEL="${2:-L1}"; shift 2 ;;
    --cadence) CADENCE="${2:-1d}"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$PATTERN" ]]; then
  echo "Usage: bash tools/loop-cost.sh <pattern> [--level L1|L2|L3] [--cadence 1d|2h|15m]"
  echo ""
  echo "Available patterns:"
  [[ -f "${PATTERNS_DIR}/registry.yaml" ]] && grep "  - id:" "${PATTERNS_DIR}/registry.yaml" | sed 's/    - id: /  - /'
  exit 1
fi

# ── Extract costs from registry ───────────────────────────────────────────
get_cost() {
  local field="$1"
  grep -A30 "id: ${PATTERN}$" "${PATTERNS_DIR}/registry.yaml" 2>/dev/null | grep -A10 "token_cost:" | grep "${field}:" | head -1 | grep -oE '[0-9]+' | head -1 || echo "0"
}

TOKENS_NOOP=$(get_cost "noop")
TOKENS_REPORT=$(get_cost "report")
TOKENS_ACTION=$(get_cost "action")
DAILY_CAP=$(get_cost "daily_cap")

# Defaults if not found
TOKENS_NOOP=${TOKENS_NOOP:-5000}
TOKENS_REPORT=${TOKENS_REPORT:-50000}
TOKENS_ACTION=${TOKENS_ACTION:-200000}
DAILY_CAP=${DAILY_CAP:-1000000}

# ── Calculate runs per day based on cadence ───────────────────────────────
case "$CADENCE" in
  2h)    RUNS_PER_DAY=12 ;;
  5m)    RUNS_PER_DAY=288 ;;
  15m)   RUNS_PER_DAY=96 ;;
  6h)    RUNS_PER_DAY=4 ;;
  1d)    RUNS_PER_DAY=1 ;;
  2d)    RUNS_PER_DAY=1 ;;
  *)     RUNS_PER_DAY=1 ;;
esac

# ── Calculate costs per level ─────────────────────────────────────────────
case "$LEVEL" in
  L1) TOKENS_PER_RUN=$TOKENS_REPORT ;;
  L2) TOKENS_PER_RUN=$TOKENS_ACTION ;;
  L3) TOKENS_PER_RUN=$((TOKENS_ACTION * 2)) ;;
  *)  TOKENS_PER_RUN=$TOKENS_REPORT ;;
esac

DAILY_COST=$((TOKENS_PER_RUN * RUNS_PER_DAY))
MONTHLY_COST=$((DAILY_COST * 22))

# ── Output ────────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════"
echo "  Loop Cost Estimate"
echo "═══════════════════════════════════════════"
echo ""
echo "Pattern:  ${PATTERN}"
echo "Level:    ${LEVEL}"
echo "Cadence:  ${CADENCE}"
echo ""
echo "── Per Run ──"
echo "  No-op:    ${TOKENS_NOOP} tokens"
echo "  Report:   ${TOKENS_REPORT} tokens"
echo "  Action:   ${TOKENS_ACTION} tokens"
echo ""
echo "── Projected Costs ──"
echo "  Runs/day:     ${RUNS_PER_DAY}"
echo "  Tokens/day:   ${DAILY_COST}"
echo "  Tokens/month: ${MONTHLY_COST}"
echo "  Daily cap:    ${DAILY_CAP}"
echo ""

if [[ $DAILY_COST -gt $DAILY_CAP ]]; then
  echo "⚠️  WARNING: Daily cost exceeds cap!"
  echo "   Suggestion: Reduce cadence or level"
else
  echo "✅ Within daily cap"
fi

echo ""
echo "── Recommendations ──"
case "$LEVEL" in
  L1)
    echo "  Week 1: Report only (no auto-fix)"
    echo "  Week 2+: Consider L2 for small fixes"
    ;;
  L2)
    echo "  Use worktree isolation for each fix"
    echo "  Require verifier sub-agent"
    echo "  Human gate on merge"
    ;;
  L3)
    echo "  ⚠️  Unattended - ensure circuit breaker is configured"
    echo "  Max iterations per fix: 5"
    echo "  Escalate after 3 consecutive failures"
    ;;
esac
echo ""
