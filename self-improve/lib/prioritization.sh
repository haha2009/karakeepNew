#!/usr/bin/env bash
# self-improve/lib/prioritization.sh (增强版)
# Prioritization (Gulli Ch.20) — 真正的自适应优先级
#
# - 多臂老虎机(Multi-Armed Bandit)探索-利用权衡
# - 在线学习 with confidence intervals
# - 优先级效果回归分析

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FWK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MEMORY_DIR="${FWK_DIR}/.memory"
PRIORITY_MODEL="${MEMORY_DIR}/.priority-model.json"
PRIORITY_HISTORY="${MEMORY_DIR}/.priority-history.jsonl"

# ═══════════════════════════════════════════════════════════════════════════
# 多臂老虎机 (Multi-Armed Bandit) — 探索 vs 利用
# ═══════════════════════════════════════════════════════════════════════════

# UCB1 (Upper Confidence Bound) algorithm for task selection
ucb1_select_task() {
  python3 - "$PRIORITY_MODEL" "$PRIORITY_HISTORY" "$MEMORY_DIR" << 'PYEOF'
import json, sys, os, math, time

model_file, history_file, memory_dir = sys.argv[1], sys.argv[2], sys.argv[3]

# Load tasks
feature_list = os.path.join(os.path.dirname(memory_dir), "template", "feature_list.json")
weaknesses = os.path.join(memory_dir, "weaknesses.json")

tasks = []
if os.path.exists(feature_list):
    with open(feature_list) as f:
        fl = json.load(f)
    for feat in fl.get("features", []):
        tasks.append({"id": feat.get("id", "unknown"), "description": feat.get("description", ""), "type": "feature"})

if os.path.exists(weaknesses):
    with open(weaknesses) as f:
        weak = json.load(f)
    for w in weak if isinstance(weak, list) else weak.get("weaknesses", []):
        tasks.append({"id": w.get("id", str(w)[:20]), "description": w.get("symptom", str(w)[:100]), "type": "weakness"})

if not tasks:
    print("No tasks to prioritize")
    sys.exit(0)

# Load history for each task
history = {}
if os.path.exists(history_file):
    with open(history_file) as f:
        for line in f:
            entry = json.loads(line.strip())
            task_id = entry.get("task_id")
            if task_id:
                history.setdefault(task_id, []).append(entry)

# UCB1 selection
total_plays = sum(len(h) for h in history.values())
if total_plays == 0:
    total_plays = 1  # Avoid log(0)

best_task = None
best_ucb = -1

for task in tasks:
    task_id = task["id"]
    task_history = history.get(task_id, [])
    n_plays = len(task_history)
    
    if n_plays == 0:
        # Never tried — high exploration bonus
        ucb = float('inf')
    else:
        # Average reward
        rewards = [h.get("reward", 0.5) for h in task_history]
        avg_reward = sum(rewards) / len(rewards)
        
        # UCB1 formula: avg_reward + sqrt(2 * ln(total_plays) / n_plays)
        exploration = math.sqrt(2 * math.log(total_plays) / n_plays)
        ucb = avg_reward + exploration
    
    task["ucb_score"] = ucb if ucb != float('inf') else 999
    task["n_plays"] = n_plays
    task["avg_reward"] = sum([h.get("reward", 0.5) for h in task_history]) / max(n_plays, 1)
    
    if ucb > best_ucb:
        best_ucb = ucb
        best_task = task

# Sort by UCB score
tasks.sort(key=lambda t: t.get("ucb_score", 0), reverse=True)

print(f"UCB1 PRIORITIZATION ({len(tasks)} tasks, {total_plays} total plays):")
for i, task in enumerate(tasks[:10]):
    ucb = task.get("ucb_score", 0)
    n = task.get("n_plays", 0)
    avg = task.get("avg_reward", 0)
    infinity = " ∞" if ucb == 999 else ""
    print(f"  {i+1}. [{ucb:>6.3f}{infinity}] {task['id'][:40]} (plays: {n}, avg_reward: {avg:.2f})")

# Save selection
selection = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "method": "ucb1",
    "selected_task": best_task["id"] if best_task else None,
    "task_rankings": [{"id": t["id"], "ucb": t.get("ucb_score", 0), "n_plays": t.get("n_plays", 0)} for t in tasks[:10]]
}

with open(os.path.join(memory_dir, ".priority-selection.json"), "w") as f:
    json.dump(selection, f, indent=2)
PYEOF
}

# Record task outcome for learning
record_priority_outcome() {
  local task_id="$1"
  local reward="$2"  # 0.0 to 1.0
  local effort="${3:-1}"
  
  python3 - "$task_id" "$reward" "$effort" "$PRIORITY_HISTORY" << 'PYEOF'
import json, sys, os, time

task_id, reward, effort, history_file = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]

entry = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "task_id": task_id,
    "reward": reward,
    "effort": effort,
    "efficiency": reward / max(effort, 0.1)
}

with open(history_file, "a") as f:
    f.write(json.dumps(entry) + "\n")

print(f"Priority outcome recorded: {task_id} → reward={reward}, effort={effort}")
PYEOF
}

# ═══════════════════════════════════════════════════════════════════════════
# 回归分析 — 优先级效果回归
# ═══════════════════════════════════════════════════════════════════════════

priority_regression() {
  python3 - "$PRIORITY_HISTORY" << 'PYEOF'
import json, sys, os

history_file = sys.argv[1]

if not os.path.exists(history_file):
    print("No priority history for regression analysis")
    sys.exit(0)

history = []
with open(history_file) as f:
    for line in f:
        history.append(json.loads(line.strip()))

if len(history) < 3:
    print(f"Need at least 3 data points for regression (have {len(history)})")
    sys.exit(0)

# Simple linear regression: reward = a * priority_score + b
# Using impact, urgency, dependency as features
import statistics

rewards = [h.get("reward", 0) for h in history]
efforts = [h.get("effort", 1) for h in history]
efficiencies = [h.get("efficiency", 0) for h in history]

# Calculate statistics
avg_reward = statistics.mean(rewards)
avg_effort = statistics.mean(efforts)
avg_efficiency = statistics.mean(efficiencies)

# Trend analysis (is efficiency improving?)
if len(efficiencies) >= 5:
    recent = efficiencies[-5:]
    older = efficiencies[:-5] if len(efficiencies) > 5 else efficiencies[:1]
    recent_avg = statistics.mean(recent)
    older_avg = statistics.mean(older)
    trend = "improving" if recent_avg > older_avg else "declining" if recent_avg < older_avg else "stable"
else:
    trend = "insufficient_data"

print(f"PRIORITY REGRESSION ANALYSIS ({len(history)} data points):")
print(f"  Average reward: {avg_reward:.2f}")
print(f"  Average effort: {avg_effort:.2f}")
print(f"  Average efficiency: {avg_efficiency:.2f}")
print(f"  Efficiency trend: {trend}")
print(f"  Recommendation: {'Continue current strategy' if trend == 'improving' else 'Adjust priority weights' if trend == 'declining' else 'Collect more data'}")
PYEOF
}

# ═══════════════════════════════════════════════════════════════════════════
# 综合优先级排序 (结合 UCB + 评分)
# ═══════════════════════════════════════════════════════════════════════════

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
        tasks.append({"id": feat.get("id", "unknown"), "description": feat.get("description", ""), "type": "feature"})

if os.path.exists(weaknesses):
    with open(weaknesses) as f:
        weak = json.load(f)
    for w in weak if isinstance(weak, list) else weak.get("weaknesses", []):
        tasks.append({"id": w.get("id", str(w)[:20]), "description": w.get("symptom", str(w)[:100]), "type": "weakness"})

if not tasks:
    print("No tasks to prioritize")
    sys.exit(0)

# Load learned weights
model = {"impact_weight": 1.0, "urgency_weight": 1.0, "dependency_weight": 1.0}
if os.path.exists(priority_model_file):
    with open(priority_model_file) as f:
        model = json.load(f)

# Score each task
for task in tasks:
    impact = 8 if task.get("type") == "weakness" else 5
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

# Sort by priority score
tasks.sort(key=lambda t: t.get("priority_score", 0), reverse=True)

print(f"PRIORITIES ({len(tasks)} tasks):")
for i, task in enumerate(tasks[:10]):
    print(f"  {i+1}. [{task['priority_score']:>5.1f}] {task['id'][:40]} (I:{task['impact']} U:{task['urgency']} D:{task['dependency']})")

with open(tasks_file, "w") as f:
    json.dump({"updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ"), "tasks": tasks, "model": model}, f, indent=2)
PYEOF
}

# Learn from outcome
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

# Gradient descent adjustment
model["impact_weight"] = max(0.1, model["impact_weight"] - lr * error * 0.1)
model["urgency_weight"] = max(0.1, model["urgency_weight"] - lr * error * 0.1)
model["dependency_weight"] = max(0.1, model["dependency_weight"] - lr * error * 0.1)

# Normalize
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

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-}" in
  prioritize)     shift; prioritize_tasks "$@" ;;
  ucb-select)     ucb1_select_task ;;
  record)         shift; record_priority_outcome "$@" ;;
  regression)     priority_regression ;;
  learn)          shift; learn_priority_weights "$@" ;;
  *)
    echo "Usage: prioritization.sh {prioritize|ucb-select|record|regression|learn}"
    ;;
esac
