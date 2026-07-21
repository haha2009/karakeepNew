#!/usr/bin/env bash
# tools/loop-init.sh — Initialize a new loop with Readiness Score
#
# Adapted from loop-engineering (cobusgreyling/loop-engineering)
# Usage: bash tools/loop-init.sh <pattern> [--tool claude|codex|opencode]
#
# Examples:
#   bash tools/loop-init.sh daily-triage
#   bash tools/loop-init.sh pr-babysitter --tool claude
#   bash tools/loop-init.sh ci-sweeper

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATTERNS_DIR="${SCRIPT_DIR}/patterns"
SKILLS_DIR="${SCRIPT_DIR}/skills"

# ── Arguments ──────────────────────────────────────────────────────────────
PATTERN="${1:-}"
TOOL="${2:-claude}"

if [[ -z "$PATTERN" ]]; then
  echo "Usage: bash tools/loop-init.sh <pattern> [--tool claude|codex|opencode]"
  echo ""
  echo "Available patterns:"
  [[ -f "${PATTERNS_DIR}/registry.yaml" ]] && grep "  - id:" "${PATTERNS_DIR}/registry.yaml" | sed 's/    - id: /  - /'
  exit 1
fi

# ── Validate pattern ───────────────────────────────────────────────────────
if ! grep -q "  - id: ${PATTERN}$" "${PATTERNS_DIR}/registry.yaml" 2>/dev/null; then
  echo "ERROR: Unknown pattern '${PATTERN}'"
  echo "Available patterns:"
  grep "  - id:" "${PATTERNS_DIR}/registry.yaml" | sed 's/    - id: /  - /'
  exit 1
fi

echo "═══════════════════════════════════════════"
echo "  MCF Loop Init"
echo "═══════════════════════════════════════════"
echo ""
echo "Pattern: ${PATTERN}"
echo "Tool:    ${TOOL}"
echo ""

# ── Create STATE.md if missing ────────────────────────────────────────────
if [[ ! -f "${SCRIPT_DIR}/STATE.md" ]]; then
  cat > "${SCRIPT_DIR}/STATE.md" << 'EOF'
# STATE.md — Loop State

> Last updated: (not yet run)

## High Priority
(No items yet)

## Watch List
(No items yet)

## Recent Noise
(No items yet)

## Loop Metrics
- Total runs: 0
- Last run: never
- Issues resolved: 0
EOF
  echo "✅ Created STATE.md"
else
  echo "⚠️  STATE.md already exists (skipped)"
fi

# ── Create LOOP.md if missing ─────────────────────────────────────────────
if [[ ! -f "${SCRIPT_DIR}/LOOP.md" ]]; then
  cat > "${SCRIPT_DIR}/LOOP.md" << EOF
# LOOP.md — Loop Configuration

## Active Loops

### ${PATTERN}
- Cadence: (see patterns/registry.yaml)
- State: STATE.md
- Skills: (auto-detected from pattern)
- Human gates: (see patterns/registry.yaml)

## Multi-loop Coordination
(Configure when running multiple loops)

## Budget & Observability
- Token budget: loop-budget.md
- Run history: loop-run-log.md
EOF
  echo "✅ Created LOOP.md"
else
  echo "⚠️  LOOP.md already exists (skipped)"
fi

# ── Create loop-budget.md if missing ──────────────────────────────────────
if [[ ! -f "${SCRIPT_DIR}/loop-budget.md" ]]; then
  cat > "${SCRIPT_DIR}/loop-budget.md" << 'EOF'
# Loop Budget

## Daily Token Budget
- Report-only (L1): 100,000 tokens/day
- Assisted fix (L2): 500,000 tokens/day
- Unattended (L3): 2,000,000 tokens/day

## Circuit Breaker
- Max consecutive failures: 3
- Max iterations per fix: 5
- Escalation: human review

## Current Usage
(Updated automatically by loop runs)
EOF
  echo "✅ Created loop-budget.md"
else
  echo "⚠️  loop-budget.md already exists (skipped)"
fi

# ── Create loop-run-log.md if missing ─────────────────────────────────────
if [[ ! -f "${SCRIPT_DIR}/loop-run-log.md" ]]; then
  cat > "${SCRIPT_DIR}/loop-run-log.md" << 'EOF'
# Loop Run Log

| Date | Pattern | Status | Tokens | Notes |
|------|---------|--------|--------|-------|
| (first run) | | | | |
EOF
  echo "✅ Created loop-run-log.md"
else
  echo "⚠️  loop-run-log.md already exists (skipped)"
fi

# ── Copy relevant skills ──────────────────────────────────────────────────
echo ""
echo "Relevant skills for ${PATTERN}:"
for skill in loop-triage loop-verifier minimal-fix; do
  if [[ -d "${SKILLS_DIR}/${skill}" ]]; then
    echo "  ✅ ${skill}/SKILL.md"
  fi
done

# ── Calculate Readiness Score ──────────────────────────────────────────────
echo ""
echo "── Readiness Score ──"

SCORE=0
CHECKS=0

# Check core files (30 pts)
for f in AGENTS.md CLAUDE.md STATE.md LOOP.md feature_list.json gate.yaml .claude/settings.json; do
  if [[ -f "${SCRIPT_DIR}/$f" ]]; then
    SCORE=$((SCORE + 4))
  fi
  CHECKS=$((CHECKS + 1))
done

# Check hooks (20 pts)
for h in .claude/hooks/protect-framework.sh .claude/hooks/protect-git.sh .claude/hooks/session-start.sh; do
  if [[ -f "${SCRIPT_DIR}/$h" ]]; then
    SCORE=$((SCORE + 6))
  fi
done

# Check libraries (20 pts)
for l in self-improve/lib/loop-guard.sh self-improve/lib/recovery.sh self-improve/lib/reflection.sh self-improve/lib/human-loop.sh self-improve/lib/self-test.sh; do
  if [[ -f "${SCRIPT_DIR}/$l" ]]; then
    SCORE=$((SCORE + 4))
  fi
done

# Check patterns & skills (15 pts)
if [[ -f "${SCRIPT_DIR}/patterns/registry.yaml" ]]; then
  SCORE=$((SCORE + 5))
fi
SKILL_COUNT=$(find "${SCRIPT_DIR}/skills" -name "SKILL.md" 2>/dev/null | wc -l)
if [[ $SKILL_COUNT -ge 3 ]]; then
  SCORE=$((SCORE + 5))
fi
if [[ -d "${SCRIPT_DIR}/tools" ]]; then
  SCORE=$((SCORE + 5))
fi

# Check budget & observability (15 pts)
for o in loop-budget.md loop-run-log.md claude-progress.md; do
  if [[ -f "${SCRIPT_DIR}/$o" ]]; then
    SCORE=$((SCORE + 5))
  fi
done

# Display score
if [[ $SCORE -ge 80 ]]; then
  EMOJI="🟢"
  STATUS="Healthy"
elif [[ $SCORE -ge 50 ]]; then
  EMOJI="🟡"
  STATUS="Warning"
else
  EMOJI="🔴"
  STATUS="Critical"
fi

echo "  ${EMOJI} Readiness Score: ${SCORE}/100 (${STATUS})"
echo ""

# ── Print first command ───────────────────────────────────────────────────
echo "═══════════════════════════════════════════"
echo "  Loop Ready!"
echo "═══════════════════════════════════════════"
echo ""
echo "First command:"
echo ""

case "$PATTERN" in
  daily-triage)
    echo "  bash self-improve.sh --loop daily-triage"
    echo ""
    echo "  Or in Claude Code:"
    echo "  /loop 1d Run loop-triage. Update STATE.md. Report only in week one."
    ;;
  pr-babysitter)
    echo "  bash self-improve.sh --loop pr-babysitter"
    ;;
  ci-sweeper)
    echo "  bash self-improve.sh --loop ci-sweeper"
    ;;
  *)
    echo "  bash self-improve.sh --loop ${PATTERN}"
    ;;
esac

echo ""
echo "Audit readiness:"
echo "  bash tools/loop-audit.sh"
echo ""
echo "Estimate cost:"
echo "  bash tools/loop-cost.sh ${PATTERN}"
echo ""
