#!/usr/bin/env bash
# self-improve/lib/exploration.sh
# Exploration & Discovery + Goal Setting & Monitoring
#
# Reference:
# - Gulli Ch.21: Exploration and Discovery — autonomous hypothesis generation
# - Gulli Ch.11: Goal Setting and Monitoring — goal lifecycle management
#
# Two modes:
# 1. Pattern-matching(default): Template-based hypothesis generation
# 2. LLM-powered(enhanced): Call LLM for creative hypothesis generation

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FWK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MEMORY_DIR="${FWK_DIR}/.memory"
EXPLORATION_LOG="${MEMORY_DIR}/.exploration-log.jsonl"
HYPOTHESIS_DB="${MEMORY_DIR}/.hypothesis-db.json"
LLM_PROVIDER="${SCRIPT_DIR}/llm-provider.sh"
explore_hypotheses() {
  local problem_space="$1"
  local context=""
  local health_file="${MEMORY_DIR}/.health-score.json"
  
  if [[ -f "$health_file" ]]; then
    context+="Health: $(python3 -c "import json;print(json.load(open('$health_file')).get('status','unknown'))" 2>/dev/null)"$'\n'
  fi
  
  local llm_status
  llm_status=$(bash "$LLM_PROVIDER" status 2>/dev/null | sed -n 's/.*Status: \([a-z]*\).*/\1/p')
  if [[ "$llm_status" != "ok" ]]; then
    llm_status=$(bash "$LLM_PROVIDER" detect 2>/dev/null | sed -n 's/LLM \([A-Z]*\).*/\1/p' | tr '[:upper:]' '[:lower:]')
    [[ "$llm_status" == "ok" ]] || llm_status=""
  fi
    
    local llm_prompt="## Problem
${problem_space}

## System Context
${context}

## Task
Generate 5 unique hypotheses for this problem. Each hypothesis should:
1. Be specific and actionable(not generic)
2. Include a concrete test to verify/falsify it
3. Have a confidence score(0-100%)
4. Cover different categories(root cause type, integration, config, etc.)

## Output Format
h1: [hypothesis description]
   Test: [how to verify]
   Confidence: [X%]
   Category: [type]

h2: ...

Be creative and specific. Avoid generic answers."
    
    local llm_result
    llm_result=$(bash "$LLM_PROVIDER" call "$llm_prompt" "" 2>/dev/null)
    
    if [[ -n "$llm_result" ]]; then
      echo "  LLM-generated hypotheses:"
      echo "$llm_result" | sed 's/^/    /'
      
      # Parse and save hypotheses
      python3 - "$problem_space" "$llm_result" "$EXPLORATION_LOG" "$context" << 'PYEOF'
import json, sys, time

problem, llm_result, exploration_log, context = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

# Parse LLM result into hypotheses
hypotheses = []
current = {}
for line in llm_result.split("\n"):
    line = line.strip()
    if line.startswith("h") and ":" in line and not line.startswith("hyp"):
        if current:
            hypotheses.append(current)
        current = {"id": line.split(":")[0].strip(), "hypothesis": line.split(":", 1)[1].strip(), "status": "pending"}
    elif line.startswith("Test:") and current:
        current["test"] = line.split(":", 1)[1].strip()
    elif line.startswith("Confidence:") and current:
        conf_str = line.split(":", 1)[1].strip().replace("%", "")
        try:
            current["confidence"] = int(conf_str) / 100
        except ValueError:
            current["confidence"] = 0.5
    elif line.startswith("Category:") and current:
        current["category"] = line.split(":", 1)[1].strip()
if current:
    hypotheses.append(current)

exploration = {
    "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "problem_space": problem[:200],
    "mode": "llm",
    "hypotheses": hypotheses,
    "context": context,
    "status": "exploring"
}

with open(exploration_log, "a") as f:
    f.write(json.dumps(exploration) + "\n")

print(f"  Generated {len(hypotheses)} hypotheses")
PYEOF
      return 0
    fi
  echo "═══ Exploration(Pattern-matching) ═══"
  
  python3 - "$problem_space" "$context" "$EXPLORATION_LOG" "$HYPOTHESIS_DB" "$MEMORY_DIR" << 'PYEOF'
import json, sys, os, time, re
  fi
  
  # Pattern-matching fallback
  echo "═══ Exploration(Pattern-matching) ═══"
  
  python3 - "$problem_space" "$context" "$EXPLORATION_LOG" "$HYPOTHESIS_DB" "$MEMORY_DIR" << 'PYEOF'
import json, sys, os, time, re

problem_space, context, exploration_log, hypothesis_db_file, memory_dir = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
desc = problem_space.lower()
hypotheses = []

patterns = {
    "performance": {
        "keywords": ["performance", "slow", "speed", "latency", "fast", "delay"],
        "hypotheses": [
            {"h": "I/O bottleneck", "test": "Profile I/O vs CPU", "base_conf": 0.5},
            {"h": "Algorithmic complexity", "test": "Measure time vs input size", "base_conf": 0.5},
            {"h": "Resource contention", "test": "Measure parallelism", "base_conf": 0.4},
            {"h": "Memory pressure", "test": "Monitor allocation", "base_conf": 0.3}
        ]
    },
    "reliability": {
        "keywords": ["reliability", "error", "crash", "fail", "unstable"],
        "hypotheses": [
            {"h": "Race condition", "test": "Add sync + load test", "base_conf": 0.5},
            {"h": "Resource exhaustion", "test": "Monitor usage over time", "base_conf": 0.5},
            {"h": "Unhandled edge case", "test": "Review error logs", "base_conf": 0.4}
        ]
    },
    "quality": {
        "keywords": ["quality", "bug", "defect", "incorrect"],
        "hypotheses": [
            {"h": "Missing validation", "test": "Add validation", "base_conf": 0.5},
            {"h": "Silent error handling", "test": "Audit catch blocks", "base_conf": 0.5},
            {"h": "State inconsistency", "test": "Audit state machine", "base_conf": 0.4}
        ]
    }
}

matched = False
for cat, pattern in patterns.items():
    if any(kw in desc for kw in pattern["keywords"]):
        for h in pattern["hypotheses"]:
            hypotheses.append({"id": f"h{len(hypotheses)+1}", "hypothesis": h["h"], "test": h["test"], "confidence": h["base_conf"], "status": "pending", "category": cat})
        matched = True

if not matched:
    hypotheses = [
        {"id": "h1", "hypothesis": f"Core logic issue in: {desc[:40]}", "test": "Isolate and test", "confidence": 0.4, "status": "pending", "category": "general"},
        {"id": "h2", "hypothesis": "Configuration mismatch", "test": "Compare environments", "confidence": 0.3, "status": "pending", "category": "general"},
        {"id": "h3", "hypothesis": "Integration point failure", "test": "Test each integration", "confidence": 0.3, "status": "pending", "category": "general"}
    ]

# Adjust confidence based on context
if "critical" in context.lower():
    for h in hypotheses:
        h["confidence"] = min(h["confidence"] + 0.2, 1.0)

exploration = {"started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "problem_space": problem[:200], "mode": "pattern", "hypotheses": hypotheses, "status": "exploring"}

with open(exploration_log, "a") as f:
    f.write(json.dumps(exploration) + "\n")

print(f"  Generated {len(hypotheses)} hypotheses:")
for h in hypotheses:
    print(f"  • {h['id']}: {h['hypothesis'][:60]}")
    print(f"    Test: {h['test']} (confidence: {h['confidence']:.0%})")
PYEOF
}

# ═══════════════════════════════════════════════════════════════════════════
# 假设验证 + 反馈循环
# ═══════════════════════════════════════════════════════════════════════════

explore_validate() {
  local hypothesis_id="$1"
  local result="$2"
  local evidence="${3:-}"
  
  python3 - "$hypothesis_id" "$result" "$evidence" "$EXPLORATION_LOG" "$HYPOTHESIS_DB" << 'PYEOF'
import json, sys, os, time

hypothesis_id, result, evidence, exploration_log, hypothesis_db_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

if not os.path.exists(exploration_log):
    print("No exploration log found")
    sys.exit(1)

# Read and update
lines = []
updated = False
confirmed_count = 0
rejected_count = 0

with open(exploration_log) as f:
    for line in f:
        try:
            entry = json.loads(line.strip())
            for h in entry.get("hypotheses", []):
                if h["id"] == hypothesis_id:
                    h["status"] = "confirmed" if result.lower() in ["true", "yes", "confirmed", "pass"] else "rejected"
                    h["result"] = result[:200]
                    h["evidence"] = evidence[:500] if evidence else ""
                    h["tested_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
                    updated = True
                if h.get("status") == "confirmed":
                    confirmed_count += 1
                elif h.get("status") == "rejected":
                    rejected_count += 1
            lines.append(json.dumps(entry))
        except json.JSONDecodeError:
            continue

with open(exploration_log, "w") as f:
    for line in lines:
        f.write(line + "\n")

if updated:
    status = "confirmed" if result.lower() in ["true", "yes", "confirmed", "pass"] else "rejected"
    print(f"Hypothesis {hypothesis_id}: {status}")
    if evidence:
        print(f"  Evidence: {evidence[:100]}")
    print(f"  Total confirmed: {confirmed_count}, rejected: {rejected_count}")
    
    # Update hypothesis database (learning)
    db = {}
    if os.path.exists(hypothesis_db_file):
        with open(hypothesis_db_file) as f:
            db = json.load(f)
    
    db[hypothesis_id] = {
        "last_result": status,
        "evidence": evidence[:200] if evidence else "",
        "tested_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "total_confirmed": confirmed_count,
        "total_rejected": rejected_count
    }
    
    with open(hypothesis_db_file, "w") as f:
        json.dump(db, f, indent=2)
else:
    print(f"Hypothesis {hypothesis_id} not found")
PYEOF
}

# ═══════════════════════════════════════════════════════════════════════════
# 探索效果度量
# ═══════════════════════════════════════════════════════════════════════════

explore_metrics() {
  python3 - "$EXPLORATION_LOG" "$HYPOTHESIS_DB" << 'PYEOF'
import json, sys, os

exploration_log, hypothesis_db_file = sys.argv[1], sys.argv[2]

if not os.path.exists(exploration_log):
    print("No exploration data available")
    sys.exit(0)

total_hypotheses = 0
confirmed = 0
rejected = 0
pending = 0
categories = {}

with open(exploration_log) as f:
    for line in f:
        try:
            entry = json.loads(line.strip())
            for h in entry.get("hypotheses", []):
                total_hypotheses += 1
                if h.get("status") == "confirmed":
                    confirmed += 1
                elif h.get("status") == "rejected":
                    rejected += 1
                else:
                    pending += 1
                cat = h.get("category", "unknown")
                categories[cat] = categories.get(cat, 0) + 1
        except json.JSONDecodeError:
            continue

print(f"EXPLORATION METRICS:")
print(f"  Total hypotheses: {total_hypotheses}")
print(f"  Confirmed: {confirmed} ({confirmed*100//max(total_hypotheses,1)}%)")
print(f"  Rejected: {rejected} ({rejected*100//max(total_hypotheses,1)}%)")
print(f"  Pending: {pending}")
print(f"  By category: {categories}")

# Hypothesis DB stats
if os.path.exists(hypothesis_db_file):
    with open(hypothesis_db_file) as f:
        db = json.load(f)
    print(f"  Hypothesis DB entries: {len(db)}")
PYEOF
}

explore_status() {
  echo "═══ Exploration Status ═══"
  explore_metrics 2>&1
}

# ═══════════════════════════════════════════════════════════════════════════
# Goal Setting (保持不变,但增强)
# ═══════════════════════════════════════════════════════════════════════════

GOALS_FILE="${MEMORY_DIR}/.goals.json"

goal_define() {
  local goal_description="$1"
  local priority="${2:-medium}"
  
  python3 - "$goal_description" "$priority" "$GOALS_FILE" << 'PYEOF'
import json, sys, time

goal_description, priority, goals_file = sys.argv[1], sys.argv[2], sys.argv[3]

goal = {
    "id": f"goal-{int(time.time())}",
    "description": goal_description,
    "priority": priority,
    "status": "defined",
    "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "subgoals": [],
    "progress": 0
}

goals = []
if __import__("os").path.exists(goals_file):
    with open(goals_file) as f:
        goals = json.load(f)

goals.append(goal)

with open(goals_file, "w") as f:
    json.dump(goals, f, indent=2)

print(f"GOAL DEFINED: {goal['id']}")
print(f"  Description: {goal_description[:60]}")
print(f"  Priority: {priority}")
PYEOF
}

goal_decompose() {
  local goal_id="$1"
  
  python3 - "$goal_id" "$GOALS_FILE" << 'PYEOF'
import json, sys, os, time

goal_id, goals_file = sys.argv[1], sys.argv[2]

if not os.path.exists(goals_file):
    print("No goals defined")
    sys.exit(1)

with open(goals_file) as f:
    goals = json.load(f)

goal = next((g for g in goals if g["id"] == goal_id), None)
if not goal:
    print(f"Goal {goal_id} not found")
    sys.exit(1)

desc = goal.get("description", "").lower()

# Smart decomposition
subgoals = []
if any(w in desc for w in ["improve", "enhance", "optimize", "better"]):
    subgoals = [
        {"id": f"{goal_id}-s1", "description": "Measure current baseline", "type": "measure"},
        {"id": f"{goal_id}-s2", "description": "Research and design improvement", "type": "research"},
        {"id": f"{goal_id}-s3", "description": "Implement incrementally with tests", "type": "implement"},
        {"id": f"{goal_id}-s4", "description": "Validate and document", "type": "validate"}
    ]
elif any(w in desc for w in ["add", "create", "implement", "build", "new"]):
    subgoals = [
        {"id": f"{goal_id}-s1", "description": "Define requirements and acceptance criteria", "type": "define"},
        {"id": f"{goal_id}-s2", "description": "Design solution architecture", "type": "design"},
        {"id": f"{goal_id}-s3", "description": "Implement core functionality with tests", "type": "implement"},
        {"id": f"{goal_id}-s4", "description": "Integrate, test, and document", "type": "integrate"}
    ]
elif any(w in desc for w in ["fix", "repair", "resolve", "debug"]):
    subgoals = [
        {"id": f"{goal_id}-s1", "description": "Reproduce and isolate the issue", "type": "reproduce"},
        {"id": f"{goal_id}-s2", "description": "Identify root cause", "type": "analyze"},
        {"id": f"{goal_id}-s3", "description": "Apply fix with regression test", "type": "fix"},
        {"id": f"{goal_id}-s4", "description": "Verify fix and add monitoring", "type": "verify"}
    ]
else:
    subgoals = [
        {"id": f"{goal_id}-s1", "description": f"Understand and plan: {desc[:40]}", "type": "plan"},
        {"id": f"{goal_id}-s2", "description": "Execute core work", "type": "execute"},
        {"id": f"{goal_id}-s3", "description": "Validate and verify", "type": "validate"}
    ]

goal["subgoals"] = subgoals
goal["status"] = "decomposed"

with open(goals_file, "w") as f:
    json.dump(goals, f, indent=2)

print(f"DECOMPOSED: {goal_id}")
print(f"  {len(subgoals)} subgoals:")
for sg in subgoals:
    print(f"    • [{sg['type']}] {sg['id']}: {sg['description']}")
PYEOF
}

goal_update_progress() {
  local goal_id="$1"
  local subgoal_id="$2"
  local status="$3"
  
  python3 - "$goal_id" "$subgoal_id" "$status" "$GOALS_FILE" << 'PYEOF'
import json, sys, os, time

goal_id, subgoal_id, status, goals_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

if not os.path.exists(goals_file):
    sys.exit(0)

with open(goals_file) as f:
    goals = json.load(f)

for goal in goals:
    if goal["id"] == goal_id:
        for sg in goal.get("subgoals", []):
            if sg["id"] == subgoal_id:
                sg["status"] = status
                sg["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        total = len(goal.get("subgoals", []))
        completed = sum(1 for sg in goal.get("subgoals", []) if sg.get("status") == "completed")
        goal["progress"] = int((completed / max(total, 1)) * 100)
        if goal["progress"] == 100:
            goal["status"] = "completed"
        elif goal["progress"] > 0:
            goal["status"] = "in_progress"
        break

with open(goals_file, "w") as f:
    json.dump(goals, f, indent=2)

print(f"Goal {goal_id}: subgoal {subgoal_id} → {status}")
PYEOF
}

goal_track() {
  echo "═══ Goal Tracking ═══"
  
  python3 - "$GOALS_FILE" << 'PYEOF'
import json, sys, os

goals_file = sys.argv[1]

if not os.path.exists(goals_file):
    print("No goals defined")
    sys.exit(0)

with open(goals_file) as f:
    goals = json.load(f)

if not goals:
    print("No goals to track")
    sys.exit(0)

for goal in goals:
    status = goal.get("status", "unknown")
    progress = goal.get("progress", 0)
    subgoals = goal.get("subgoals", [])
    emoji = "🟢" if status == "completed" else "🟡" if status == "in_progress" else "⚪"
    print(f"{emoji} {goal['id']}: {goal['description'][:50]}")
    print(f"   Status: {status} | Progress: {progress}%")
    if subgoals:
        completed = sum(1 for sg in subgoals if sg.get("status") == "completed")
        print(f"   Subgoals: {completed}/{len(subgoals)} completed")
PYEOF
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-}" in
  explore)            shift; explore_hypotheses "$@" ;;
  validate)           shift; explore_validate "$@" ;;
  explore-metrics)    explore_metrics ;;
  explore-status)     explore_status ;;
  goal-define)        shift; goal_define "$@" ;;
  goal-decompose)     shift; goal_decompose "$@" ;;
  goal-update)        shift; goal_update_progress "$@" ;;
  goal-track)         goal_track ;;
  *)
    echo "Usage: exploration.sh {explore|validate|explore-metrics|explore-status|goal-define|goal-decompose|goal-update|goal-track}"
    ;;
esac
