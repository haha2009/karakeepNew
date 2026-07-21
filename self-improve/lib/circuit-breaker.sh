#!/usr/bin/env bash
# self-improve/lib/circuit-breaker.sh
# Token cost circuit breaker for self-improvement loop
# Prevents runaway token costs (inspired by Ch16's $2000/3days anecdote)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_IMPROVE_DIR="$(dirname "$SCRIPT_DIR")"
MEMORY_DIR="${SELF_IMPROVE_DIR}/.memory"
STATE_FILE="${MEMORY_DIR}/.cb-state.json"

# Thresholds
SINGLE_TASK_MAX=10000
BATCH_MAX=50000
HOOK_MAX_SHARE=0.3

init_state() {
  mkdir -p "$MEMORY_DIR"
  [[ -f "$STATE_FILE" ]] || echo '{"tokens_used":0,"hooks_called":0}' > "$STATE_FILE"
}

record_usage() {
  local tokens="$1"
  python3 - "$STATE_FILE" "$tokens" << 'PYEOF'
import json, sys, time
state_file, tokens = sys.argv[1], int(sys.argv[2])
state = json.load(open(state_file))
state["tokens_used"] = state.get("tokens_used", 0) + tokens
state["hooks_called"] = state.get("hooks_called", 0) + 1
json.dump(state, open(state_file, "w"), indent=2)
PYEOF
}

check_budget() {
  local estimated_tokens="${1:-1000}"
  init_state
  python3 - "$STATE_FILE" "$estimated_tokens" << 'PYEOF'
import json, sys
state_file, estimated = sys.argv[1], int(sys.argv[2])
state = json.load(open(state_file))
total = state.get("tokens_used", 0) + estimated
hooks = state.get("hooks_called", 0)
if estimated > 10000:
    print(f"BLOCK: single task {estimated} > max 10000")
    sys.exit(1)
if total > 50000:
    print(f"BLOCK: batch total {total} > max 50000")
    sys.exit(1)
if hooks > 10 and estimated / total > 0.3:
    print(f"BLOCK: hook share {estimated}/{total} > 0.3")
    sys.exit(1)
print(f"ALLOW: {total}/50000 tokens, {hooks} hooks")
sys.exit(0)
PYEOF
}

report() {
  init_state
  python3 - "$STATE_FILE" << 'PYEOF'
import json, sys
state = json.load(open(sys.argv[1]))
print(f"Tokens used: {state.get('tokens_used', 0)}")
print(f"Hooks called: {state.get('hooks_called', 0)}")
PYEOF
}

case "${1:-report}" in
  record) record_usage "$2" ;;
  check) check_budget "$2" ;;
  *) report ;;
esac
