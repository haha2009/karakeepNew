#!/usr/bin/env bash
# tools/loop-audit.sh — Audit loop readiness (0-100 score)
#
# Adapted from loop-engineering (cobusgreyling/loop-engineering)
# Usage: bash tools/loop-audit.sh [--suggest] [--badge]
#
# Scores 0-100 with concrete next steps.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUGGEST=false
BADGE=false

for arg in "$@"; do
  case "$arg" in
    --suggest) SUGGEST=true ;;
    --badge) BADGE=true ;;
  esac
done

SCORE=0
ISSUES=0
WARNINGS=0

echo "═══════════════════════════════════════════"
echo "  MCF Loop Audit"
echo "═══════════════════════════════════════════"
echo ""

# ── Check 1: Core files exist (30 points) ─────────────────────────────────
echo "── Core Files (30 pts) ──"
CORE_FILES=(
  "AGENTS.md"
  "CLAUDE.md"
  "STATE.md"
  "LOOP.md"
  "feature_list.json"
  "gate.yaml"
  ".claude/settings.json"
)

for f in "${CORE_FILES[@]}"; do
  if [[ -f "${SCRIPT_DIR}/$f" ]]; then
    echo "  ✅ $f"
    SCORE=$((SCORE + 4))
  else
    echo "  ❌ $f (missing)"
    ISSUES=$((ISSUES + 1))
  fi
done
echo ""

# ── Check 2: Hooks (20 points) ────────────────────────────────────────────
echo "── Hooks (20 pts) ──"
HOOKS=(
  ".claude/hooks/protect-framework.sh"
  ".claude/hooks/protect-git.sh"
  ".claude/hooks/session-start.sh"
)

for h in "${HOOKS[@]}"; do
  if [[ -f "${SCRIPT_DIR}/$h" ]]; then
    echo "  ✅ $h"
    SCORE=$((SCORE + 6))
  else
    echo "  ⚠️  $h (missing)"
    WARNINGS=$((WARNINGS + 1))
  fi
done
echo ""

# ── Check 3: Self-improve libraries (20 points) ────────────────────────────
echo "── Self-Improve Libraries (20 pts) ──"
LIBS=(
  "self-improve/lib/loop-guard.sh"
  "self-improve/lib/recovery.sh"
  "self-improve/lib/reflection.sh"
  "self-improve/lib/human-loop.sh"
  "self-improve/lib/self-test.sh"
)

for l in "${LIBS[@]}"; do
  if [[ -f "${SCRIPT_DIR}/$l" ]]; then
    echo "  ✅ $l"
    SCORE=$((SCORE + 4))
  else
    echo "  ❌ $l (missing)"
    ISSUES=$((ISSUES + 1))
  fi
done
echo ""

# ── Check 4: Patterns & Skills (15 points) ────────────────────────────────
echo "── Patterns & Skills (15 pts) ──"
if [[ -f "${SCRIPT_DIR}/patterns/registry.yaml" ]]; then
  echo "  ✅ patterns/registry.yaml"
  SCORE=$((SCORE + 5))
else
  echo "  ❌ patterns/registry.yaml (missing)"
  ISSUES=$((ISSUES + 1))
fi

SKILL_COUNT=$(find "${SCRIPT_DIR}/skills" -name "SKILL.md" 2>/dev/null | wc -l)
if [[ $SKILL_COUNT -ge 3 ]]; then
  echo "  ✅ skills/ (${SKILL_COUNT} skills)"
  SCORE=$((SCORE + 5))
else
  echo "  ⚠️  skills/ (only ${SKILL_COUNT}, recommend 3+)"
  WARNINGS=$((WARNINGS + 1))
fi

if [[ -d "${SCRIPT_DIR}/tools" ]]; then
  echo "  ✅ tools/"
  SCORE=$((SCORE + 5))
else
  echo "  ❌ tools/ (missing)"
  ISSUES=$((ISSUES + 1))
fi
echo ""

# ── Check 5: Budget & Observability (15 points) ────────────────────────────
echo "── Budget & Observability (15 pts) ──"
OBS_FILES=(
  "loop-budget.md"
  "loop-run-log.md"
  "claude-progress.md"
)

for o in "${OBS_FILES[@]}"; do
  if [[ -f "${SCRIPT_DIR}/$o" ]]; then
    echo "  ✅ $o"
    SCORE=$((SCORE + 5))
  else
    echo "  ⚠️  $o (missing)"
    WARNINGS=$((WARNINGS + 1))
  fi
done
echo ""

# ── Check 6: Integrations (bonus 10 points) ───────────────────────────────
echo "── Integrations (bonus 10 pts) ──"
INTEGRATIONS=(
  "integrations/graphiti/graphiti-adapter.sh"
  "integrations/opik/opik-adapter.sh"
  "integrations/graph-engineering/graph-workflow.sh"
)

for i in "${INTEGRATIONS[@]}"; do
  if [[ -f "${SCRIPT_DIR}/$i" ]]; then
    echo "  ✅ $i"
    SCORE=$((SCORE + 3))
  else
    echo "  ⚠️  $i (missing)"
  fi
done
echo ""

# ── Summary ───────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════"
echo "  Audit Result"
echo "═══════════════════════════════════════════"
echo ""

if [[ $SCORE -ge 80 ]]; then
  echo "  Score: ${SCORE}/100 🟢 Healthy"
elif [[ $SCORE -ge 50 ]]; then
  echo "  Score: ${SCORE}/100 🟡 Warning"
else
  echo "  Score: ${SCORE}/100 🔴 Critical"
fi

echo "  Issues: ${ISSUES}"
echo "  Warnings: ${WARNINGS}"

# ── Suggestions ───────────────────────────────────────────────────────────
if [[ "$SUGGEST" == true ]] && [[ $ISSUES -gt 0 || $WARNINGS -gt 0 ]]; then
  echo ""
  echo "── Suggestions ──"
  
  if [[ ! -f "${SCRIPT_DIR}/patterns/registry.yaml" ]]; then
    echo "  1. Create patterns/registry.yaml (copy from MCF template)"
  fi
  
  if [[ ! -d "${SCRIPT_DIR}/tools" ]]; then
    echo "  2. Create tools/ directory with loop-init.sh, loop-audit.sh"
  fi
  
  if [[ $SKILL_COUNT -lt 3 ]]; then
    echo "  3. Add more skills to skills/ (loop-triage, loop-verifier, minimal-fix)"
  fi
  
  echo ""
  echo "  Run: bash tools/loop-init.sh daily-triage"
fi

# ── Badge ─────────────────────────────────────────────────────────────────
if [[ "$BADGE" == true ]]; then
  echo ""
  if [[ $SCORE -ge 80 ]]; then
    echo "  ![Loop Ready](https://img.shields.io/badge/Loop-Ready-${SCORE}%25-green)"
  elif [[ $SCORE -ge 50 ]]; then
    echo "  ![Loop Ready](https://img.shields.io/badge/Loop-Ready-${SCORE}%25-yellow)"
  else
    echo "  ![Loop Ready](https://img.shields.io/badge/Loop-Ready-${SCORE}%25-red)"
  fi
fi

echo ""

# Exit code based on score
if [[ $SCORE -ge 50 ]]; then
  exit 0
else
  exit 1
fi
