#!/usr/bin/env bash
# integrations/opik/opik-adapter.sh
# Opik Observability Adapter for MCF

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/.data"
OPIK_DATA="${DATA_DIR}/opik-data.json"

mkdir -p "$DATA_DIR"

# ── Initialize ────────────────────────────────────────────────────────────
init_opik() {
  if [[ ! -f "$OPIK_DATA" ]]; then
    echo '{"traces": [], "metrics": []}' > "$OPIK_DATA"
  fi
  echo "✅ Opik initialized at ${DATA_DIR}"
}

# ── Trace an operation ────────────────────────────────────────────────────
trace_operation() {
  local name="${1:-}"
  local command="${2:-}"
  
  [[ -z "$name" ]] && { echo "Usage: trace <name> <command>"; return 1; }
  
  local start_time
  start_time=$(date +%s%N)
  
  local output
  local exit_code=0
  output=$(eval "$command" 2>&1) || exit_code=$?
  
  local end_time
  end_time=$(date +%s%N)
  local duration_ms=$(( (end_time - start_time) / 1000000 ))
  
  # Record trace
  python3 - "$name" "$exit_code" "$duration_ms" "$output" "$OPIK_DATA" << 'PYEOF'
import json, sys, os, time

name, exit_code, duration_ms, output, data_file = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]

with open(data_file) as f:
    data = json.load(f)

trace = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "name": name,
    "status": "success" if exit_code == 0 else "error",
    "duration_ms": duration_ms,
    "output": output[:500]
}

data.setdefault("traces", []).append(trace)

# Keep only last 1000 traces
if len(data["traces"]) > 1000:
    data["traces"] = data["traces"][-1000:]

with open(data_file, "w") as f:
    json.dump(data, f, indent=2)

status = "OK" if exit_code == 0 else "FAIL"
print(f"{status} {name}: {duration_ms}ms (exit: {exit_code})")
PYEOF
  
  return $exit_code
}

# ── Record metric ─────────────────────────────────────────────────────────
record_metric() {
  local name="${1:-}"
  local value="${2:-}"
  
  python3 - "$name" "$value" "$OPIK_DATA" << 'PYEOF'
import json, sys, os, time

name, value, data_file = sys.argv[1], sys.argv[2], sys.argv[3]

with open(data_file) as f:
    data = json.load(f)

  python3 - "$OPIK_DATA" << 'PYEOF'
import json, os, sys
from collections import Counter

data_file = sys.argv[1]
    "value": value
}

data.setdefault("metrics", []).append(metric)

if len(data["metrics"]) > 500:
    data["metrics"] = data["metrics"][-500:]

with open(data_file, "w") as f:
    json.dump(data, f, indent=2)

print(f"Recorded: {name} = {value}")
PYEOF
}

# ── Dashboard ──────────────────────────────────────────────────────────────
show_dashboard() {
  python3 - "$OPIK_DATA" << 'PYEOF'
import json, os
from collections import Counter

data_file = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), ".data", "opik-data.json")

with open(data_file) as f:
    data = json.load(f)

traces = data.get("traces", [])
metrics = data.get("metrics", [])

print("=" * 45)
print("  Opik Observability Dashboard")
print("=" * 45)
print(f"Total traces: {len(traces)}")
print(f"Total metrics: {len(metrics)}")
print()

if traces:
    success_count = sum(1 for t in traces if t.get("status") == "success")
    error_count = len(traces) - success_count
    success_rate = (success_count / len(traces)) * 100
    print("Success Rate:")
    print(f"  OK: {success_count}")
    print(f"  FAIL: {error_count}")
    print(f"  Rate: {success_rate:.1f}%")
    print()
    
    durations = [t.get("duration_ms", 0) for t in traces]
    avg_duration = sum(durations) / len(durations) if durations else 0
    print("Performance:")
    print(f"  Avg duration: {avg_duration:.0f}ms")
    print()
    
    print("Recent Traces:")
    for trace in traces[-10:]:
        status = "OK" if trace.get("status") == "success" else "FAIL"
        print(f"  [{status}] {trace.get('name', '?')}: {trace.get('duration_ms', 0)}ms")

if metrics:
    print()
    print("Recent Metrics:")
    for metric in metrics[-10:]:
        print(f"  {metric.get('name', '?')}: {metric.get('value', '?')}")
PYEOF
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-dashboard}" in
  init)       init_opik ;;
  trace)      shift; trace_operation "$@" ;;
  metric)     shift; record_metric "$@" ;;
  dashboard)  show_dashboard ;;
  *)          echo "Usage: bash opik-adapter.sh {init|trace|metric|dashboard}" ;;
esac
