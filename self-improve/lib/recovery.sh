#!/usr/bin/env bash
# self-improve/lib/recovery.sh
# Exception Handling & Recovery pattern
#
# Reference: Gulli "Agentic Design Patterns" Ch.12 — Exception Handling and Recovery
# Error detection → classification → recovery strategy → retry/degrade/pause

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FWK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MEMORY_DIR="${FWK_DIR}/.memory"
STATE_FILE="${MEMORY_DIR}/.recovery-state.json"

# ── Thresholds ──────────────────────────────────────────────────────────────
MAX_RETRIES=3                 # Max retry attempts for transient errors
RETRY_BASE_DELAY=2            # Base delay in seconds (exponential backoff)
RETRY_MAX_DELAY=30            # Max delay between retries
CIRCUIT_BREAKER_THRESHOLD=5   # Errors before circuit opens
CIRCUIT_BREAKER_TIMEOUT=60    # Seconds before circuit half-opens

# ── Error classification ───────────────────────────────────────────────────
# Transient: network timeout, rate lock, temporary resource exhaustion → retry
# Permanent: config error, permission denied, invalid input → degrade + alert
# Unknown: can't classify → pause + human

classify_error() {
  local error_msg="$1"
  local exit_code="${2:-1}"
  
  # Transient patterns
  if echo "$error_msg" | grep -qiE "(timeout|rate.limit|temporary|unavailable|503|502|429|connection.refused|EOF|reset.by.peer)"; then
    echo "transient"
    return
  fi
  
  # Permanent patterns
  if echo "$error_msg" | grep -qiE "(permission.denied|forbidden|403|401|invalid|not.found|404|config|unauthorized|denied)"; then
    echo "permanent"
    return
  fi
  
  # Unknown
  echo "unknown"
}

# ── Recovery strategy selector ─────────────────────────────────────────────
select_recovery_strategy() {
  local error_class="$1"
  local retry_count="$2"
  
  case "$error_class" in
    transient)
      if [[ "$retry_count" -lt $MAX_RETRIES ]]; then
        echo "retry"
      else
        echo "degrade"
      fi
      ;;
    permanent)
      echo "degrade"
      ;;
    unknown)
      if [[ "$retry_count" -lt 2 ]]; then
        echo "retry"
      else
        echo "pause"
      fi
      ;;
  esac
}

# ── Exponential backoff delay ───────────────────────────────────────────────
compute_delay() {
  local retry_count="$1"
  local delay=$(( RETRY_BASE_DELAY * (2 ** (retry_count - 1)) ))
  [[ $delay -gt $RETRY_MAX_DELAY ]] && delay=$RETRY_MAX_DELAY
  echo "$delay"
}

# ── Circuit breaker ─────────────────────────────────────────────────────────
check_circuit_breaker() {
  local service="${1:-self-improve}"
  
  python3 - "$STATE_FILE" "$service" << 'PYEOF'
import json, sys, time, os

state_file, service = sys.argv[1], sys.argv[2]

state = {}
if os.path.exists(state_file):
    with open(state_file) as f:
        state = json.load(f)

service_state = state.get(service, {"errors": 0, "last_error": 0, "status": "closed"})
now = time.time()

# Check if circuit is open
if service_state["status"] == "open":
    elapsed = now - service_state["last_error"]
    if elapsed >= 60:  #Circuit breaker timeout
        service_state["status"] = "half-open"
        print("HALF_OPEN")
    else:
        print("OPEN")
        sys.exit(1)
elif service_state["status"] == "half-open":
    print("HALF_OPEN")
else:
    print("CLOSED")

state[service] = service_state
with open(state_file, "w") as f:
    json.dump(state, f, indent=2)
sys.exit(0)
PYEOF
}

record_success() {
  local service="${1:-self-improve}"
  
  python3 - "$STATE_FILE" "$service" << 'PYEOF'
import json, sys, os

state_file, service = sys.argv[1], sys.argv[2]

state = {}
if os.path.exists(state_file):
    with open(state_file) as f:
        state = json.load(f)

state[service] = {"errors": 0, "last_error": 0, "status": "closed"}

with open(state_file, "w") as f:
    json.dump(state, f, indent=2)
PYEOF
}

record_error() {
  local service="${1:-self-improve}"
  local error_msg="${2:-unknown}"
  
  python3 - "$STATE_FILE" "$service" "$error_msg" << 'PYEOF'
import json, sys, time, os

state_file, service, error_msg = sys.argv[1], sys.argv[2], sys.argv[3]

state = {}
if os.path.exists(state_file):
    with open(state_file) as f:
        state = json.load(f)

service_state = state.get(service, {"errors": 0, "last_error": 0, "status": "closed"})

service_state["errors"] = service_state.get("errors", 0) + 1
service_state["last_error"] = time.time()
service_state["last_error_msg"] = error_msg[:200]

# Check circuit breaker threshold
if service_state["errors"] >= 5:
    service_state["status"] = "open"
elif service_state["errors"] >= 3:
    service_state["status"] = "half-open"

state[service] = service_state

with open(state_file, "w") as f:
    json.dump(state, f, indent=2)

print(f"Error recorded: {service_state['errors']} total, status={service_state['status']}")
PYEOF
}

# ── Execute with recovery ──────────────────────────────────────────────────
# Usage: run_with_recovery <command> [args...]
# Returns: 0 on success, 1 if all recovery exhausted
run_with_recovery() {
  local retry_count=0
  local last_error=""
  local last_exit_code=0
  
  while true; do
    # Check circuit breaker
    local cb_status
    cb_status=$(check_circuit_breaker 2>/dev/null || echo "CLOSED")
    if [[ "$cb_status" == "OPEN" ]]; then
      echo "🚫 Circuit breaker OPEN — pausing operations"
      return 1
    fi
    
    # Execute the command
    local output
    output=$("$@" 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
      record_success
      return 0
    fi
    
    # Error occurred
    last_error="$output"
    last_exit_code=$exit_count
    retry_count=$((retry_count + 1))
    
    # Classify the error
    local error_class
    error_class=$(classify_error "$last_error" "$exit_code")
    
    # Select recovery strategy
    local strategy
    strategy=$(select_recovery_strategy "$error_class" "$retry_count")
    
    echo "⚠️  Error (attempt ${retry_count}): class=${error_class}, strategy=${strategy}"
    echo "   Last error: ${last_error:0:100}"
    
    case "$strategy" in
      retry)
        local delay
        delay=$(compute_delay "$retry_count")
        echo "   Retrying in ${delay}s..."
        sleep "$delay"
        ;;
      degrade)
        echo "🔽 Degrading to safe state — skipping non-critical operations"
        record_error "self-improve" "${last_error:0:200}"
        return 1
        ;;
      pause)
        echo "⏸️  Pausing for manual intervention"
        record_error "self-improve" "${last_error:0:200}"
        # Write pause marker for human
        cat > "${MEMORY_DIR}/.pause-marker.json" << PAUSE_EOF
{
  "paused_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "reason": "${last_error:0:500}",
  "retry_count": ${retry_count},
  "error_class": "${error_class}",
  "action_required": "Review the error and run 'self-improve.sh resume' to continue"
}
PAUSE_EOF
        return 1
        ;;
    esac
  done
}

# ── Status ──────────────────────────────────────────────────────────────────
recovery_status() {
  echo "═══ Exception Recovery Status ═══"
  if [[ -f "$STATE_FILE" ]]; then
    python3 - "$STATE_FILE" << 'PYEOF'
import json, sys, time
state = json.load(open(sys.argv[1]))
for service, s in state.items():
    status = s.get("status", "unknown")
    errors = s.get("errors", 0)
    last = s.get("last_error", 0)
    ago = f"{int(time.time() - last)}s ago" if last else "never"
    emoji = "🟢" if status == "closed" else "🟡" if status == "half-open" else "🔴"
    print(f"  {emoji} {service}: {status} ({errors} errors, last: {ago})")
PYEOF
  else
    echo "  No recovery state"
  fi
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-status}" in
  classify)   shift; classify_error "$@" ;;
  strategy)   shift; select_recovery_strategy "$@" ;;
  run)        shift; run_with_recovery "$@" ;;
  record-err) shift; record_error "$@" ;;
  record-ok)  shift; record_success "$@" ;;
  status)     recovery_status ;;
  *)          echo "Usage: recovery.sh {classify|strategy|run <cmd>|record-err|record-ok|status}" ;;
esac
