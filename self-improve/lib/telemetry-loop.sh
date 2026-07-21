#!/usr/bin/env bash
# self-improve/lib/telemetry-loop.sh
# Telemetry Closed-Loop Decision Making
#
# Reference: Bot audit "Data collection without consumption" + my verification
# Closes the loop: telemetry → evaluation → decision → action
#
# v1.4: Health score influences loop behavior

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FWK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MEMORY_DIR="${FWK_DIR}/.memory"
HEALTH_FILE="${MEMORY_DIR}/.health-score.json"

# ── Check health score and decide action ──────────────────────────────────
# Returns: 0 = proceed, 1 = warn+continue, 2 = pause+alert
check_health_and_decide() {
  [[ ! -f "$HEALTH_FILE" ]] && return 0
  
  local score status
  score=$(python3 -c "import json;print(json.load(open('$HEALTH_FILE')).get('overall_score', 100))" 2>/dev/null)
  score=${score:-100}
  status=$(python3 -c "import json;print(json.load(open('$HEALTH_FILE')).get('status', 'unknown'))" 2>/dev/null)
  status=${status:-unknown}
  
  # Critical: pause loop
  if [[ $(echo "$score < 50" | bc -l 2>/dev/null || echo "0") -eq 1 ]] || [[ "$status" == "critical" ]]; then
    echo "🛑 CRITICAL: Health score ${score}/100 (${status})" >&2
    echo "   Action: Loop paused. Review .memory/.health-score.json" >&2
    return 2
  fi
  
  # Degraded: warn but continue
  if [[ $(echo "$score < 70" | bc -l 2>/dev/null || echo "0") -eq 1 ]] || [[ "$status" == "degraded" ]]; then
    echo "⚠️ DEGRADED: Health score ${score}/100 (${status})" >&2
    echo   "Action: Continuing with caution" >&2
    return 1
  fi
  
  return 0
}

# ── Record telemetry event ────────────────────────────────────────────────
record_event() {
  local event_type="$1"
  local payload="${2:-}"
  local telemetry_file="${MEMORY_DIR}/framework-telemetry.jsonl"
  
  python3 - "$event_type" "$payload" "$telemetry_file" << 'PYEOF'
import json, sys, time
event_type, payload, f = sys.argv[1], sys.argv[2], sys.argv[3]
event = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "type": event_type,
    "payload": payload[:200] if payload else ""
}
with open(f, "a") as fh:
    fh.write(json.dumps(event) + "\n")
PYEOF
}

# ── Get telemetry summary ────────────────────────────────────────────────
telemetry_summary() {
  echo "═══ Telemetry Summary ═══"
  local telemetry_file="${MEMORY_DIR}/framework-telemetry.jsonl"
  
  if [[ ! -f "$telemetry_file" ]]; then
    echo "  No telemetry data"
    return
  fi
  
  python3 - "$telemetry_file" << 'PYEOF'
import json, sys, collections
f = sys.argv[1]
events = [json.loads(l) for l in open(f) if l.strip()]
if not events:
    print("  No events")
    exit(0)
print(f"  Total events: {len(events)}")
counts = collections.Counter(e.get("type", "unknown") for e in events)
for event_type, count in counts.most_common(10):
    print(f"    {event_type}: {count}")
PYEOF
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-summary}" in
  check)      check_health_and_decide ;;
  record)     shift; record_event "$@" ;;
  summary)    telemetry_summary ;;
  *)          echo "Usage: telemetry-loop.sh {check|record|summary}" ;;
esac
