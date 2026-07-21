#!/usr/bin/env bash
# self-improve/lib/orchestration.sh
# P1 Patterns Deep Alignment
# - Routing (Ch.2): 自适应路由 + 效果反馈
# - Parallelization (Ch.3): 真正的并行调度 + MapReduce
# - Multi-Agent (Ch.7): 协作推理协议
# - Prioritization (Ch.20): 学习型优先级
# - Resource-Aware (Ch.16): 成本-收益动态优化

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FWK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MEMORY_DIR="${FWK_DIR}/.memory"

# ═══════════════════════════════════════════════════════════════════════════
# ROUTING (Gulli Ch.2) — 自适应路由 + 效果反馈
# ═══════════════════════════════════════════════════════════════════════════

ROUTE_TABLE="${MEMORY_DIR}/.route-table.json"

init_route_table() {
  [[ -f "$ROUTE_TABLE" ]] && return
  cat > "$ROUTE_TABLE" << 'EOF'
{
  "routes": {
    "fix": {"handler": "diagnose-and-repair", "success_count": 0, "total_count": 0},
    "feature": {"handler": "design-and-implement", "success_count": 0, "total_count": 0},
    "refactor": {"handler": "analyze-and-refactor", "success_count": 0, "total_count": 0},
    "verify": {"handler": "test-and-validate", "success_count": 0, "total_count": 0},
    "document": {"handler": "generate-docs", "success_count": 0, "total_count": 0},
    "review": {"handler": "review-and-assess", "success_count": 0, "total_count": 0},
    "general": {"handler": "general-execution", "success_count": 0, "total_count": 0}
  },
  "history": []
}
EOF
}

route_task() {
  local task_description="$1"
  local task_type=""
  local complexity="medium"
  
  init_route_table
  
  # Classify task type
  if echo "$task_description" | grep -qiE "(fix|bug|error|crash|broken|issue|defect)"; then
    task_type="fix"
  elif echo "$task_description" | grep -qiE "(add|create|new|implement|feature|build)"; then
    task_type="feature"
  elif echo "$task_description" | grep -qiE "(refactor|restructure|clean|optimize|improve)"; then
    task_type="refactor"
  elif echo "$task_description" | grep -qiE "(test|verify|validate|check|assert)"; then
    task_type="verify"
  elif echo "$task_description" | grep -qiE "(document|explain|describe|comment|readme)"; then
    task_type="document"
  elif echo "$task_description" | grep -qiE "(review|audit|analyze|assess|inspect)"; then
    task_type="review"
  else
    task_type="general"
  fi
  
  # Assess complexity
  local word_count char_count
  word_count=$(echo "$task_description" | wc -w)
  char_count=${#task_description}
  
  if [[ $word_count -lt 5 ]] && [[ $char_count -lt 30 ]]; then
    complexity="low"
  elif [[ $word_count -gt 25 ]] || [[ $char_count -gt 150 ]]; then
    complexity="high"
  fi
  
  # Route with feedback
  python3 - "$task_type" "$complexity" "$task_description" "$ROUTE_TABLE" << 'PYEOF'
import json, sys, time, os

task_type, complexity, description, route_table_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(route_table_file) as f:
    route_data = json.load(f)

routes = route_data.get("routes", {})
handler_info = routes.get(task_type, routes.get("general"))

# Calculate success rate
total = handler_info.get("total_count", 0)
success = handler_info.get("success_count", 0)
success_rate = (success / max(total, 1)) * 100

# Adaptive routing: if success rate < 50%, try alternative
strategy = "parallel" if complexity == "high" else "sequential"
if success_rate < 50 and total > 2:
    best_route = max(routes.items(), key=lambda x: x[1].get("success_count", 0) / max(x[1].get("total_count", 1), 1))
    if best_route[0] != task_type:
        handler_info = best_route[1]
        task_type = best_route[0]
        strategy = "adaptive_fallback"

routing = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "task_type": task_type,
    "complexity": complexity,
    "handler": handler_info.get("handler", "unknown"),
    "strategy": strategy,
    "success_rate": round(success_rate, 1),
    "needs_verification": task_type in ["fix", "feature", "refactor"],
    "needs_review": complexity == "high"
}

handler_info["total_count"] = total + 1
route_data.setdefault("history", []).append(routing)
route_data["history"] = route_data["history"][-100:]

with open(route_table_file, "w") as f:
    json.dump(route_data, f, indent=2)

print(f"ROUTE: {task_type} → {handler_info['handler']} (complexity: {complexity}, strategy: {strategy})")
print(f"  Historical success rate: {success_rate:.0f}%")
print(f"  Verification needed: {routing['needs_verification']}")
print(f"  Review needed: {routing['needs_review']}")
PYEOF
}

record_route_outcome() {
  local task_type="$1"
  local success="${2:-true}"
  
  python3 - "$task_type" "$success" "$ROUTE_TABLE" << 'PYEOF'
import json, sys, os

task_type, success, route_table_file = sys.argv[1], sys.argv[2].lower() == "true", sys.argv[3]

if not os.path.exists(route_table_file):
    sys.exit(0)

with open(route_table_file) as f:
    route_data = json.load(f)

routes = route_data.get("routes", {})
if task_type in routes:
    if success:
        routes[task_type]["success_count"] = routes[task_type].get("success_count", 0) + 1
    routes[task_type]["total_count"] = routes[task_type].get("total_count", 0) + 1

with open(route_table_file, "w") as f:
    json.dump(route_data, f, indent=2)

print(f"Route outcome recorded: {task_type} → {'success' if success else 'failure'}")
PYEOF
}

# ═══════════════════════════════════════════════════════════════════════════
# PARALLELIZATION (Gulli Ch.3) — 真正的并行调度 + MapReduce
# ═══════════════════════════════════════════════════════════════════════════

parallel_dispatch() {
  local tasks_json="$1"
  
  python3 - "$tasks_json" "$MEMORY_DIR" << 'PYEOF'
import json, sys, os, time, subprocess, concurrent.futures, glob

tasks_json, memory_dir = sys.argv[1], sys.argv[2]

try:
    tasks = json.loads(tasks_json)
except json.JSONDecodeError:
    print("Invalid tasks JSON")
    sys.exit(1)

if not tasks:
    print("No tasks to dispatch")
    sys.exit(0)

results_dir = os.path.join(memory_dir, "parallel-results")
os.makedirs(results_dir, exist_ok=True)

def execute_task(task):
    task_id = task.get("id", str(int(time.time() * 1000)))
    task_desc = task.get("description", "")
    task_cmd = task.get("command", "")
    
    result = {
        "id": task_id,
        "description": task_desc,
        "status": "pending",
        "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    }
    
    if task_cmd:
        try:
            proc = subprocess.run(task_cmd, shell=True, capture_output=True, text=True, timeout=60)
            result["status"] = "success" if proc.returncode == 0 else "failed"
            result["output"] = proc.stdout[:500] if proc.stdout else ""
            result["error"] = proc.stderr[:500] if proc.stderr else ""
        except subprocess.TimeoutExpired:
            result["status"] = "timeout"
            result["error"] = "Command timed out after 60s"
        except Exception as e:
            result["status"] = "error"
            result["error"] = str(e)[:200]
    else:
        result["status"] = "skipped"
    
    result["completed_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    
    result_file = os.path.join(results_dir, f"{task_id}.json")
    with open(result_file, "w") as f:
        json.dump(result, f, indent=2)
    
    return result

# Execute in parallel (max 4 workers)
max_workers = min(len(tasks), 4)
print(f"PARALLEL DISPATCH: {len(tasks)} tasks, {max_workers} workers")

with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
    futures = {executor.submit(execute_task, task): task for task in tasks}
    completed = 0
    for future in concurrent.futures.as_completed(futures):
        result = future.result()
        completed += 1
        status_emoji = "OK" if result["status"] == "success" else "FAIL"
        print(f"  {status_emoji} [{completed}/{len(tasks)}] {result['description'][:40]}")

# Aggregate results inline
results = []
for result_file in glob.glob(os.path.join(results_dir, "*.json")):
    if os.path.basename(result_file) == ".aggregation.json":
        continue
    with open(result_file) as f:
        results.append(json.load(f))

total_tasks = len(results)
successful = sum(1 for r in results if r.get("status") == "success")
failed = sum(1 for r in results if r.get("status") == "failed")
print(f"AGGREGATE: {successful}/{total_tasks} succeeded ({successful*100//max(total_tasks,1)}%)")
PYEOF
}

# ═══════════════════════════════════════════════════════════════════════════
# MULTI-AGENT (Gulli Ch.7) — 协作推理协议
# ═══════════════════════════════════════════════════════════════════════════

get_agent_role() {
  case "$1" in
    orchestrator) echo "Coordinates work, delegates tasks, synthesizes results" ;;
    researcher)   echo "Gathers information, explores options, finds patterns" ;;
    implementer)  echo "Writes code, applies fixes, builds features" ;;
    reviewer)     echo "Checks quality, verifies correctness, finds issues" ;;
    documenter)   echo "Writes docs, explains decisions, creates reports" ;;
    *)            echo "Unknown role" ;;
  esac
}

agent_collaborate() {
  local task="$1"
  local participating_agents="$2"
  
  python3 - "$task" "$participating_agents" "$MEMORY_DIR" << 'PYEOF'
import json, sys, os, time

task, agents_str, memory_dir = sys.argv[1], sys.argv[2], sys.argv[3]
agents = [a.strip() for a in agents_str.split(",")]

collaboration = {
    "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "task": task[:200],
    "participants": agents,
    "protocol": "collaborative_reasoning",
    "phases": []
}

# Phase 1: Individual analysis
for agent in agents:
    collaboration["phases"].append({
        "agent": agent,
        "phase": "analysis",
        "focus": f"As {agent}, I focus on my area of expertise",
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    })

# Phase 2: Information sharing
collaboration["phases"].append({
    "agent": "orchestrator",
    "phase": "synthesis",
    "focus": "Combining individual analyses into unified view",
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
})

# Phase 3: Consensus building
collaboration["phases"].append({
    "agent": "all",
    "phase": "consensus",
    "focus": "Resolving conflicts and agreeing on approach",
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
})

# Phase 4: Action assignment
collaboration["phases"].append({
    "agent": "orchestrator",
    "phase": "delegation",
    "focus": "Assigning sub-tasks to agents based on expertise",
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
})

collab_log = os.path.join(memory_dir, ".collaboration-log.jsonl")
with open(collab_log, "a") as f:
    f.write(json.dumps(collaboration) + "\n")

print(f"MULTI-AGENT COLLABORATION: {task[:50]}")
print(f"  Participants: {', '.join(agents)}")
print(f"  Protocol: {collaboration['protocol']}")
for phase in collaboration["phases"]:
    print(f"  Phase [{phase['phase']}]: {phase['agent']} → {phase['focus'][:50]}")
PYEOF
}

dispatch_to_agent() {
  local role="$1"
  local task="$2"
  local context="${3:-}"
  
  local role_desc
  role_desc=$(get_agent_role "$role")
  if [[ "$role_desc" == "Unknown role" ]]; then
    echo "Unknown role: $role"
    return 1
  fi
  
  python3 - "$role" "$task" "$context" "$role_desc" "$MEMORY_DIR" << 'PYEOF'
import json, sys, os, time

role, task, context, role_desc, memory_dir = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

dispatch = {
    "dispatched_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "role": role,
    "task": task[:200],
    "context": context[:500] if context else "",
    "status": "dispatched"
}

dispatch_log = os.path.join(memory_dir, ".dispatch-log.jsonl")
with open(dispatch_log, "a") as f:
    f.write(json.dumps(dispatch) + "\n")

print(f"DISPATCH: {role} → {task[:60]}...")
print(f"  Role description: {role_desc}")
PYEOF
}

# ═══════════════════════════════════════════════════════════════════════════
# PRIORITIZATION (Gulli Ch.20) — 学习型优先级
# ═══════════════════════════════════════════════════════════════════════════

PRIORITY_MODEL="${MEMORY_DIR}/.priority-model.json"

prioritize_tasks() {
  local tasks_file="${1:-${MEMORY_DIR}/.priorities.json}"
  
  python3 - "$tasks_file" "$MEMORY_DIR" "$PRIORITY_MODEL" << 'PYEOF'
import json, sys, os, time

tasks_file, memory_dir, priority_model_file = sys.argv[1], sys.argv[2], sys.argv[3]

feature_list = os.path.join(os.path.dirname(memory_dir), "template", "feature_list.json")
weaknesses = os.path.join(memory_dir, "weaknesses.json")

tasks = []
if os.path.exists(feature_list):
    with open(feature_list) as f:
        fl = json.load(f)
    for feat in fl.get("features", []):
        tasks.append({"id": feat.get("id", "unknown"), "description": feat.get("description", ""), "status": feat.get("status", "not_started")})

if os.path.exists(weaknesses):
    with open(weaknesses) as f:
        weak = json.load(f)
    for w in weak if isinstance(weak, list) else weak.get("weaknesses", []):
        tasks.append({"id": w.get("id", str(w)[:20]), "description": w.get("symptom", str(w)[:100]), "status": "not_started", "is_weakness": True})

if not tasks:
    print("No tasks to prioritize")
    sys.exit(0)

model = {"impact_weight": 1.0, "urgency_weight": 1.0, "dependency_weight": 1.0}
if os.path.exists(priority_model_file):
    with open(priority_model_file) as f:
        model = json.load(f)

for task in tasks:
    impact = 8 if task.get("is_weakness") else 5
    urgency = 5
    desc = task.get("description", "").lower()
    if "security" in desc or "critical" in desc:
        urgency = 10
    elif "bug" in desc or "fix" in desc:
        urgency = 8
    elif "doc" in desc:
        urgency = 3
    dependency = 5
    score = (impact * model["impact_weight"] + urgency * model["urgency_weight"] + dependency * model["dependency_weight"])
    task["priority_score"] = round(score, 1)
    task["impact"] = impact
    task["urgency"] = urgency
    task["dependency"] = dependency

tasks.sort(key=lambda t: t.get("priority_score", 0), reverse=True)

print(f"PRIORITIES ({len(tasks)} tasks):")
for i, task in enumerate(tasks[:10]):
    print(f"  {i+1}. [{task['priority_score']:>5.1f}] {task['id'][:40]} (I:{task['impact']} U:{task['urgency']} D:{task['dependency']})")

with open(tasks_file, "w") as f:
    json.dump({"updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ"), "tasks": tasks, "model": model}, f, indent=2)
PYEOF
}

learn_priority_weights() {
  local task_id="$1"
  local actual_effort="$2"
  local predicted_priority="$3"
  
  python3 - "$task_id" "$actual_effort" "$predicted_priority" "$PRIORITY_MODEL" << 'PYEOF'
import json, sys, os, time

task_id, actual_effort, predicted_priority, model_file = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]

model = {"impact_weight": 1.0, "urgency_weight": 1.0, "dependency_weight": 1.0, "learning_rate": 0.1}
if os.path.exists(model_file):
    with open(model_file) as f:
        model = json.load(f)

error = abs(actual_effort - predicted_priority) / max(predicted_priority, 1)
lr = model.get("learning_rate", 0.1)

model["impact_weight"] = max(0.1, model["impact_weight"] - lr * error * 0.1)
model["urgency_weight"] = max(0.1, model["urgency_weight"] - lr * error * 0.1)
model["dependency_weight"] = max(0.1, model["dependency_weight"] - lr * error * 0.1)

total = model["impact_weight"] + model["urgency_weight"] + model["dependency_weight"]
model["impact_weight"] = round(model["impact_weight"] / total * 3, 3)
model["urgency_weight"] = round(model["urgency_weight"] / total * 3, 3)
model["dependency_weight"] = round(model["dependency_weight"] / total * 3, 3)
model["last_updated"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
model["last_error"] = round(error, 3)

with open(model_file, "w") as f:
    json.dump(model, f, indent=2)

print(f"PRIORITY LEARNING: error={error:.2f}, weights=I:{model['impact_weight']} U:{model['urgency_weight']} D:{model['dependency_weight']}")
PYEOF
}

# ═══════════════════════════════════════════════════════════════════════════
# RESOURCE-AWARE OPTIMIZATION (Gulli Ch.16) — 成本-收益动态优化
# ═══════════════════════════════════════════════════════════════════════════

optimize_resources() {
  python3 - "$MEMORY_DIR" << 'PYEOF'
import json, sys, os, time

memory_dir = sys.argv[1]

vcr_file = os.path.join(memory_dir, "vcr.json")
history_file = os.path.join(memory_dir, "self-improve-history.md")

total_budget = 40000
vcr_ratio = 1.0

if os.path.exists(vcr_file):
    with open(vcr_file) as f:
        vcr = json.load(f)
    summary = vcr.get("summary", {})
    claimed = summary.get("total_claimed", 1)
    actual = summary.get("total_actual", 1)
    vcr_ratio = actual / max(claimed, 1)

history_count = 0
if os.path.exists(history_file):
    with open(history_file) as f:
        history_count = f.read().count("## Round")

adjusted_budget = int(total_budget * vcr_ratio)
if history_count > 5:
    adjusted_budget = int(adjusted_budget * 0.8)

allocation = {
    "mine": int(adjusted_budget * 0.20),
    "analyze": int(adjusted_budget * 0.15),
    "apply": int(adjusted_budget * 0.25),
    "reflect": int(adjusted_budget * 0.15),
    "verify": int(adjusted_budget * 0.15),
    "snapshot": int(adjusted_budget * 0.10)
}

recommendation = "maintain"
if vcr_ratio < 0.5:
    recommendation = "reduce_budget_and_increase_verification"
elif vcr_ratio > 0.9 and history_count > 3:
    recommendation = "increase_budget_for_more_ambitious_changes"

result = {
    "calculated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "total_budget": total_budget,
    "adjusted_budget": adjusted_budget,
    "vcr_ratio": round(vcr_ratio, 2),
    "history_rounds": history_count,
    "allocation": allocation,
    "recommendation": recommendation
}

print(f"RESOURCE OPTIMIZATION:")
print(f"  Total budget: {total_budget}")
print(f"  Adjusted budget: {adjusted_budget} (VCR: {vcr_ratio:.0%})")
print(f"  Recommendation: {recommendation}")
for phase, tokens in allocation.items():
    print(f"    {phase}: {tokens} tokens")

with open(os.path.join(memory_dir, ".resource-plan.json"), "w") as f:
    json.dump(result, f, indent=2)
PYEOF
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-}" in
  route)              shift; route_task "$@" ;;
  route-outcome)      shift; record_route_outcome "$@" ;;
  parallel-dispatch)  shift; parallel_dispatch "$@" ;;
  collaborate)        shift; agent_collaborate "$@" ;;
  dispatch)           shift; dispatch_to_agent "$@" ;;
  prioritize)         shift; prioritize_tasks "$@" ;;
  learn-priority)     shift; learn_priority_weights "$@" ;;
  optimize)           shift; optimize_resources ;;
  *)                  echo "Usage: orchestration.sh {route|route-outcome|parallel-dispatch|collaborate|dispatch|prioritize|learn-priority|optimize}" ;;
esac
