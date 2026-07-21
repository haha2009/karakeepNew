#!/usr/bin/env bash
# self-improve/lib/evaluation.sh
# Evaluation & Monitoring (Gulli Ch.19) — SLA/SLI + Alerting + Health Score
#
# Reference: Gulli "Agentic Design Patterns" Ch.19 — Evaluation and Monitoring
# - Define SLA targets (Service Level Agreements)
# - Measure SLIs (Service Level Indicators)
# - Alert when SLIs violate SLA
# - Overall health scoring

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FWK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MEMORY_DIR="${FWK_DIR}/.memory"
SLA_CONFIG="${MEMORY_DIR}/.sla-config.json"
SLI_LOG="${MEMORY_DIR}/.sli-log.jsonl"
ALERT_LOG="${MEMORY_DIR}/.alert-log.jsonl"
HEALTH_FILE="${MEMORY_DIR}/.health-score.json"

# ═══════════════════════════════════════════════════════════════════════════
# SLA/SLI 定义与测量
# ═══════════════════════════════════════════════════════════════════════════

init_sla_config() {
  [[ -f "$SLA_CONFIG" ]] && return
  cat > "$SLA_CONFIG" << 'EOF'
{
  "slas": {
    "hook_response_time_ms": {"target": 500, "warning": 400, "critical": 500, "unit": "ms"},
    "verification_pass_rate": {"target": 0.95, "warning": 0.90, "critical": 0.80, "unit": "ratio"},
    "vcr_minimum": {"target": 0.80, "warning": 0.70, "critical": 0.50, "unit": "ratio"},
    "self_improve_success_rate": {"target": 0.90, "warning": 0.80, "critical": 0.60, "unit": "ratio"},
    "token_budget_usage": {"target": 0.80, "warning": 0.90, "critical": 0.95, "unit": "ratio"},
    "loop_iteration_count": {"target": 5, "warning": 8, "critical": 10, "unit": "count"},
    "checkpoint_frequency": {"target": 0.80, "warning": 0.60, "critical": 0.40, "unit": "ratio"},
    "ralph_wiggum_rate": {"target": 0.0, "warning": 0.10, "critical": 0.20, "unit": "ratio"}
  },
  "weights": {
    "hook_response_time_ms": 0.15,
    "verification_pass_rate": 0.20,
    "vcr_minimum": 0.15,
    "self_improve_success_rate": 0.15,
    "token_budget_usage": 0.10,
    "loop_iteration_count": 0.10,
    "checkpoint_frequency": 0.05,
    "ralph_wiggum_rate": 0.10
  }
}
EOF
}

# Measure SLIs
measure_slis() {
  init_sla_config
  
  python3 - "$MEMORY_DIR" "$SLA_CONFIG" "$SLI_LOG" << 'PYEOF'
import json, sys, os, time

memory_dir, sla_config_file, sli_log_file = sys.argv[1], sys.argv[2], sys.argv[3]

with open(sla_config_file) as f:
    sla_config = json.load(f)

slas = sla_config.get("slas", {})
measurements = {}

# Measure each SLI
for sla_name, sla_def in slas.items():
    value = None
    
    if sla_name == "hook_response_time_ms":
        # Average hook response time from timing log
        timing_file = os.path.join(memory_dir, "hook-timing.log")
        if os.path.exists(timing_file):
            with open(timing_file) as f:
                times = []
                for line in f:
                    if "SLOW:" in line:
                        import re
                        match = re.search(r'(\d+)ms', line)
                        if match:
                            times.append(int(match.group(1)))
                value = sum(times) / len(times) if times else 50
        else:
            value = 50  # default
    
    elif sla_name == "verification_pass_rate":
        vcr_file = os.path.join(memory_dir, "vcr.json")
        if os.path.exists(vcr_file):
            with open(vcr_file) as f:
                vcr = json.load(f)
            summary = vcr.get("summary", {})
            claimed = summary.get("total_claimed", 1)
            actual = summary.get("total_actual", 1)
            value = actual / max(claimed, 1)
        else:
            value = 1.0
    
    elif sla_name == "vcr_minimum":
        vcr_file = os.path.join(memory_dir, "vcr.json")
        if os.path.exists(vcr_file):
            with open(vcr_file) as f:
                vcr = json.load(f)
            records = vcr.get("records", [])
            if records:
                rates = [r.get("actual", 0) / max(r.get("claimed", 1), 1) for r in records[-10:]]
                value = min(rates) if rates else 1.0
            else:
                value = 1.0
        else:
            value = 1.0
    
    elif sla_name == "self_improve_success_rate":
        state_file = os.path.join(memory_dir, ".loop-state.json")
        if os.path.exists(state_file):
            with open(state_file) as f:
                state = json.load(f)
            iterations = state.get("iterations", [])
            if iterations:
                successful = sum(1 for it in iterations if it.get("action_sig") != "static")
                value = successful / len(iterations)
            else:
                value = 1.0
        else:
            value = 1.0
    
    elif sla_name == "token_budget_usage":
        resource_file = os.path.join(memory_dir, ".resource-plan.json")
        if os.path.exists(resource_file):
            with open(resource_file) as f:
                plan = json.load(f)
            adjusted = plan.get("adjusted_budget", 40000)
            value = adjusted / 40000
        else:
            value = 0.8
    
    elif sla_name == "loop_iteration_count":
        state_file = os.path.join(memory_dir, ".loop-state.json")
        if os.path.exists(state_file):
            with open(state_file) as f:
                state = json.load(f)
            value = len(state.get("iterations", []))
        else:
            value = 0
    
    elif sla_name == "checkpoint_frequency":
        checkpoint_file = os.path.join(memory_dir, ".checkpoint.json")
        state_file = os.path.join(memory_dir, ".loop-state.json")
        if os.path.exists(checkpoint_file) and os.path.exists(state_file):
            with open(state_file) as f:
                state = json.load(f)
            iterations = len(state.get("iterations", []))
            value = 1.0 if iterations > 0 else 0.0
        else:
            value = 0.0
    
    elif sla_name == "ralph_wiggum_rate":
        state_file = os.path.join(memory_dir, ".loop-state.json")
        if os.path.exists(state_file):
            with open(state_file) as f:
                state = json.load(f)
            status = state.get("status", "running")
            iterations = state.get("iterations", [])
            # Check for repeated action signatures
            if len(iterations) >= 3:
                recent = [it.get("action_sig", "") for it in iterations[-3:]]
                if len(set(recent)) == 1:
                    value = 1.0
                else:
                    value = 0.0
            else:
                value = 0.0
        else:
            value = 0.0
    
    if value is not None:
        measurements[sla_name] = round(value, 4)

# Log SLI measurement
entry = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "measurements": measurements
}

with open(sli_log_file, "a") as f:
    f.write(json.dumps(entry) + "\n")

print("SLI MEASUREMENTS:")
for name, value in measurements.items():
    sla = slas.get(name, {})
    target = sla.get("target", "?")
    unit = sla.get("unit", "")
    print(f"  {name}: {value}{unit} (target: {target}{unit})")
PYEOF
}

# ═══════════════════════════════════════════════════════════════════════════
# 健康评分系统
# ═══════════════════════════════════════════════════════════════════════════

calculate_health_score() {
  init_sla_config
  
  python3 - "$SLA_CONFIG" "$SLI_LOG" "$HEALTH_FILE" << 'PYEOF'
import json, sys, os, time

sla_config_file, sli_log_file, health_file = sys.argv[1], sys.argv[2], sys.argv[3]

with open(sla_config_file) as f:
    sla_config = json.load(f)

slas = sla_config.get("slas", {})
weights = sla_config.get("weights", {})

# Get latest SLI measurements
latest_measurements = {}
if os.path.exists(sli_log_file):
    with open(sli_log_file) as f:
        lines = f.readlines()
        if lines:
            latest = json.loads(lines[-1].strip())
            latest_measurements = latest.get("measurements", {})

if not latest_measurements:
    print("No SLI measurements available")
    sys.exit(1)

# Calculate component scores (0-100 each)
component_scores = {}
violations = []

for sla_name, sla_def in slas.items():
    value = latest_measurements.get(sla_name)
    if value is None:
        continue
    
    target = sla_def.get("target", 0)
    warning = sla_def.get("warning", 0)
    critical = sla_def.get("critical", 0)
    
    # For "lower is better" metrics
    lower_is_better = sla_name in ["hook_response_time_ms", "loop_iteration_count", "ralph_wiggum_rate", "token_budget_usage"]
    
    if lower_is_better:
        if value <= target:
            score = 100
        elif value <= warning:
            score = 80
        elif value <= critical:
            score = 50
            violations.append(f"{sla_name}: {value} <= {critical} (critical)")
        else:
            score = 20
            violations.append(f"{sla_name}: {value} > {critical} (CRITICAL)")
    else:
        # For "higher is better" metrics
        if value >= target:
            score = 100
        elif value >= warning:
            score = 80
        elif value >= critical:
            score = 50
            violations.append(f"{sla_name}: {value} <= {critical} (critical)")
        else:
            score = 20
            violations.append(f"{sla_name}: {value} < {critical} (CRITICAL)")
    
    component_scores[sla_name] = score

# Calculate weighted overall score
total_weight = sum(weights.get(name, 0) for name in component_scores)
if total_weight > 0:
    overall_score = sum(
        component_scores[name] * weights.get(name, 0)
        for name in component_scores
    ) / total_weight
else:
    overall_score = 100

# Determine health status
if overall_score >= 90:
    status = "healthy"
    emoji = "🟢"
elif overall_score >= 70:
    status = "degraded"
    emoji = "🟡"
elif overall_score >= 50:
    status = "at_risk"
    emoji = "🟠"
else:
    status = "critical"
    emoji = "🔴"

health = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "overall_score": round(overall_score, 1),
    "status": status,
    "component_scores": component_scores,
    "violations": violations
}

with open(health_file, "w") as f:
    json.dump(health, f, indent=2)

print(f"HEALTH SCORE: {emoji} {overall_score:.0f}/100 ({status})")
for name, score in component_scores.items():
    bar = "█" * int(score / 10) + "░" * (10 - int(score / 10))
    print(f"  {name:30} {bar} {score:.0f}")
if violations:
    print(f"\nActive violations ({len(violations)}):")
    for v in violations:
        print(f"  ⚠️  {v}")
PYEOF
}

# ═══════════════════════════════════════════════════════════════════════════
# 告警机制
# ═══════════════════════════════════════════════════════════════════════════

check_alerts() {
  init_sla_config
  
  python3 - "$SLA_CONFIG" "$SLI_LOG" "$ALERT_LOG" << 'PYEOF'
import json, sys, os, time

sla_config_file, sli_log_file, alert_log_file = sys.argv[1], sys.argv[2], sys.argv[3]

with open(sla_config_file) as f:
    sla_config = json.load(f)

slas = sla_config.get("slas", {})

# Get latest SLI measurements
latest_measurements = {}
if os.path.exists(sli_log_file):
    with open(sli_log_file) as f:
        lines = f.readlines()
        if lines:
            latest = json.loads(lines[-1].strip())
            latest_measurements = latest.get("measurements", {})

if not latest_measurements:
    print("No SLI measurements available for alerting")
    sys.exit(1)

alerts = []

for sla_name, sla_def in slas.items():
    value = latest_measurements.get(sla_name)
    if value is None:
        continue
    
    target = sla_def.get("target", 0)
    critical = sla_def.get("critical", 0)
    
    lower_is_better = sla_name in ["hook_response_time_ms", "loop_iteration_count", "ralph_wiggum_rate", "token_budget_usage"]
    
    severity = None
    if lower_is_better:
        if value > critical:
            severity = "CRITICAL"
        elif value > target * 1.5:
            severity = "WARNING"
    else:
        if value < critical:
            severity = "CRITICAL"
        elif value < target * 0.8:
            severity = "WARNING"
    
    if severity:
        alert = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "metric": sla_name,
            "value": value,
            "threshold": critical if severity == "CRITICAL" else target,
            "severity": severity,
            "action_required": severity == "CRITICAL"
        }
        alerts.append(alert)

# Log alerts
if alerts:
    with open(alert_log_file, "a") as f:
        for alert in alerts:
            f.write(json.dumps(alert) + "\n")
    
    print(f"ALERTS ({len(alerts)} active):")
    for alert in alerts:
        emoji = "🔴" if alert["severity"] == "CRITICAL" else "🟡"
        action = " — ACTION REQUIRED" if alert["action_required"] else ""
        print(f"  {emoji} [{alert['severity']}] {alert['metric']}: {alert['value']} (threshold: {alert['threshold']}){action}")
else:
    print("✅ No active alerts — all metrics within SLA")
    sys.exit(0)

sys.exit(1 if any(a["severity"] == "CRITICAL" for a in alerts) else 0)
PYEOF
}

# ═══════════════════════════════════════════════════════════════════════════
# 状态展示
# ═══════════════════════════════════════════════════════════════════════════

evaluation_status() {
  echo "═══ Evaluation & Monitoring Status ═══"
  
  if [[ -f "$HEALTH_FILE" ]]; then
    python3 - "$HEALTH_FILE" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    health = json.load(f)
score = health.get("overall_score", "?")
status = health.get("status", "unknown")
emoji = "🟢" if status == "healthy" else "🟡" if status == "degraded" else "🟠" if status == "at_risk" else "🔴"
print(f"  {emoji} Health Score: {score}/100 ({status})")
PYEOF
  else
    echo "  No health score calculated yet"
  fi
  
  if [[ -f "$ALERT_LOG" ]]; then
    local alert_count
    alert_count=$(wc -l < "$ALERT_LOG" 2>/dev/null || echo 0)
    echo "  Total alerts logged: ${alert_count}"
  fi
  
  if [[ -f "$SLI_LOG" ]]; then
    local sli_count
    sli_count=$(wc -l < "$SLI_LOG" 2>/dev/null || echo 0)
    echo "  SLI measurements: ${sli_count}"
  fi
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-status}" in
  init-sla)       init_sla_config; echo "SLA config initialized" ;;
  measure)        measure_slis ;;
  health)         calculate_health_score ;;
  check-alerts)   check_alerts ;;
  status)         evaluation_status ;;
  *)
    echo "Usage: evaluation.sh {init-sla|measure|health|check-alerts|status}"
    ;;
esac
