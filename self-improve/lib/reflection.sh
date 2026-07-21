#!/usr/bin/env bash
# self-improve/lib/reflection.sh
# Reflection pattern — self-evaluation → revision → re-evaluation loop
#
# Reference: Gulli "Agentic Design Patterns" Ch.4 — Reflection
#
# Two modes:
# 1. Heuristic(default): 5-dimension scoring with Python scripts
# 2. LLM-powered(enhanced): Call LLM for deep analysis and revision suggestions

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FWK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MEMORY_DIR="${FWK_DIR}/.memory"
REPORT_FILE="${MEMORY_DIR}/.reflection-report.json"
LLM_PROVIDER="${SCRIPT_DIR}/llm-provider.sh"

MAX_REFLECTION_ROUNDS=3
MIN_QUALITY_SCORE=7

# ── LLM-powered reflection ─────────────────────────────────────────────────

reflect_on_changes() {
  local analysis_file="${MEMORY_DIR}/.analysis.md"
  local changes_summary
  changes_summary=$(cd "$FWK_DIR" && git diff --stat 2>/dev/null | tail -1 || echo "no changes")
  
  # Check if LLM is available
  local llm_status
  llm_status=$(bash "$LLM_PROVIDER" status 2>/dev/null | sed -n 's/.*Status: \([a-z]*\).*/\1/p')
  if [[ "$llm_status" != "ok" ]]; then
    llm_status=$(bash "$LLM_PROVIDER" detect 2>/dev/null | sed -n 's/LLM \([A-Z]*\).*/\1/p' | tr '[:upper:]' '[:lower:]')
    [[ "$llm_status" == "ok" ]] || llm_status=""
  fi
  
  if [[ "$llm_status" == "ok" ]]; then
    echo "  Using LLM-powered analysis..."
    local diff_content
    diff_content=$(cd "$FWK_DIR" && git diff 2>/dev/null | head -100)
    
    local llm_prompt="## Task
Evaluate the following code changes for quality.

## Change Summary
${changes_summary}

## Diff
${diff_content}

## Analysis Document
$(cat "$analysis_file" 2>/dev/null || echo "None")

## Score each dimension 1-10
1. Correctness: Does the change actually fix the issue?
2. Completeness: Are all aspects addressed?
3. Coherence: Does it fit existing code style?
4. Safety: Does it introduce new risks?
5. Verifiability: Can it be tested?

## Output Format
Scores: Correctness=X, Completeness=X, Coherence=X, Safety=X, Verifiability=X
Overall: X/10
Verdict: PASS/FAIL
Issues: (list specific issues)
Suggestions: (specific improvement suggestions)"
    
    local llm_result
    llm_result=$(bash "$LLM_PROVIDER" call "$llm_prompt" "" 2>/dev/null)
    
    if [[ -n "$llm_result" ]]; then
      echo "  LLM Analysis:"
      echo "$llm_result" | sed 's/^/    /'
      
      local overall verdict
      overall=$(echo "$llm_result" | grep "Overall:" | grep -oE '[0-9]+/10' | cut -d/ -f1)
      overall=${overall:-5}
      verdict=$(echo "$llm_result" | grep "Verdict:" | awk '{print $2}')
      verdict=${verdict:-FAIL}
      
      python3 - "$MEMORY_DIR" "$overall" "$verdict" "$llm_result" << 'PYEOF'
import json, sys
memory_dir, overall, verdict, llm_result = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
result = {
    "mode": "llm", "overall": int(overall), "verdict": verdict,
    "llm_analysis": llm_result[:500],
    "scores": {"correctness": 5, "completeness": 5, "coherence": 5, "safety": 5, "verifiability": 5},
    "issues": [], "revision_suggestions": [], "changed_files": []
}
json.dump(result, open(f"{memory_dir}/.reflection-report.json", "w"), indent=2)
print(f"REFLECTION(LLM): {verdict} (score: {overall}/10)")
PYEOF
      
      [[ "$verdict" == "PASS" ]] && return 0 || return 1
    fi
  fi
  
  # Heuristic fallback
  echo "  Using heuristic analysis..."
  python3 - "$FWK_DIR" "$MEMORY_DIR" "$changes_summary" << 'PYEOF'
import json, sys, os, re, subprocess

fwk_dir, memory_dir, changes_summary = sys.argv[1], sys.argv[2], sys.argv[3]
scores = {"correctness": 5, "completeness": 5, "coherence": 5, "safety": 5, "verifiability": 5}
issues = []
suggestions = []

try:
    diff_output = subprocess.check_output(["git", "diff"], cwd=fwk_dir, stderr=subprocess.DEVNULL).decode("utf-8", errors="replace")
except subprocess.CalledProcessError:
    diff_output = ""

try:
    changed_files = subprocess.check_output(["git", "diff", "--name-only"], cwd=fwk_dir, stderr=subprocess.DEVNULL).decode("utf-8", errors="replace").strip().split("\n")
except subprocess.CalledProcessError:
    changed_files = []

if diff_output:
    lines_added = diff_output.count("\n+") - diff_output.count("\n+++")
    lines_removed = diff_output.count("\n-") - diff_output.count("\n---")
    if lines_added + lines_removed < 3:
        scores["completeness"] = 3
        issues.append("Changes appear minimal")
    else:
        scores["completeness"] = 7
    if re.search(r'^\+.*(TODO|FIXME|XXX|HACK)\b', diff_output, re.MULTILINE):
        scores["correctness"] = 4
        issues.append("New TODO/FIXME introduced")
    if re.search(r'^\+.*(console\.log|debugger|print\()', diff_output, re.MULTILINE):
        scores["correctness"] = 3
        issues.append("Debug statements found")
    if re.search(r'^\+.*(API_KEY|SECRET|PASSWORD|TOKEN)\s*=\s*["\'][^"\']{8,}["\']', diff_output, re.MULTILINE):
        scores["safety"] = 1
        issues.append("POTENTIAL SECRET LEAK")

core_files = [".claude/hooks/protect-framework.sh", ".claude/hooks/protect-git.sh", "AGENTS.md", "CLAUDE.md"]
for f in changed_files:
    if f in core_files:
        scores["safety"] = max(scores["safety"] - 3, 1)
        issues.append(f"Core file modified: {f}")

if any("test" in f.lower() or "spec" in f.lower() for f in changed_files):
    scores["verifiability"] = 8
else:
    scores["verifiability"] = 4
    suggestions.append("Consider adding tests")

overall = sum(scores.values()) // len(scores)
verdict = "PASS" if overall >= 7 and not any("POTENTIAL SECRET" in i for i in issues) else "FAIL"

result = {"mode": "heuristic", "scores": scores, "overall": overall, "verdict": verdict, "issues": issues, "revision_suggestions": suggestions, "changed_files": changed_files, "changes_summary": changes_summary}
json.dump(result, open(f"{memory_dir}/.reflection-report.json", "w"), indent=2)
print(f"REFLECTION: {verdict} (score: {overall}/10)")
if issues:
    print(f"Issues ({len(issues)}):")
    for issue in issues:
        print(f"  - {issue}")
PYEOF
}

# ── Revise ─────────────────────────────────────────────────────────────────

revise_changes() {
  local report_file="${MEMORY_DIR}/.reflection-report.json"
  [[ ! -f "$report_file" ]] && { echo "No reflection report"; return 1; }
  echo "── Revising based on reflection ──"
  echo "(Auto-fix not yet implemented - manual review required)"
  return 0
}

# ── Full reflection loop ───────────────────────────────────────────────────

run_reflection_loop() {
  local round=0
  while [[ $round -lt $MAX_REFLECTION_ROUNDS ]]; do
    round=$((round + 1))
    echo ""
    echo "── Reflection Round ${round}/${MAX_REFLECTION_ROUNDS} ──"
    if reflect_on_changes; then
      echo "✅ Reflection PASSED"
      return 0
    fi
    if [[ $round -ge $MAX_REFLECTION_ROUNDS ]]; then
      echo "❌ Reflection FAILED after ${MAX_REFLECTION_ROUNDS} rounds"
      return 1
    fi
    echo "Attempting revision..."
    revise_changes || true
  done
  return 1
}

# ── CLI ──────────────────────────────────────────────────────────────────────

case "${1:-}" in
  reflect)    reflect_on_changes ;;
  revise)     revise_changes ;;
  loop)       run_reflection_loop ;;
  *)          echo "Usage: reflection.sh {reflect|revise|loop}" ;;
esac
