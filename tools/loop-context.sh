#!/usr/bin/env bash
# tools/loop-context.sh — Memory manager + circuit breaker
#
# Adapted from loop-engineering (cobusgreyling/loop-engineering)
# Usage:
#   bash tools/loop-context.sh check --ledger loop-ledger.json
#   bash tools/loop-context.sh record --ledger loop-ledger.json --run-id <id> --status <ok|fail>
#   bash tools/loop-context.sh memory --key <key> --value <value>
#   bash tools/loop-context.sh memory-get --key <key>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${SCRIPT_DIR}/.memory"
MEMORY_FILE="${DATA_DIR}/loop-memory.json"

mkdir -p "$DATA_DIR"

# ── Circuit Breaker ───────────────────────────────────────────────────────
check_circuit() {
  local ledger_file="${1:-}"
  
  if [[ ! -f "$ledger_file" ]]; then
    echo "CONTINUE (no ledger)"
    return 0
  fi
  
  python3 - "$ledger_file" << 'PYEOF'
import json, sys

ledger_file = sys.argv[1]
with open(ledger_file) as f:
    ledger = json.load(f)

runs = ledger.get("runs", [])
if not runs:
    print("CONTINUE (no runs)")
    sys.exit(0)

# Check last 3 runs
last_3 = runs[-3:]
failures = sum(1 for r in last_3 if r.get("status") == "fail")

if failures >= 3:
    print("ESCALATE: 3+ consecutive failures")
    sys.exit(2)

# Check if same error repeating
errors = [r.get("error", "") for r in last_3 if r.get("error")]
if len(errors) >= 2 and len(set(errors)) == 1:
    print("ESCALATE: same error repeating")
    sys.exit(2)

print("CONTINUE")
sys.exit(0)
PYEOF
}

record_run() {
  local ledger_file="${1:-}"
  local run_id="${2:-}"
  local status="${3:-ok}"
  local error="${4:-}"
  
  mkdir -p "$(dirname "$ledger_file")"
  
  python3 - "$ledger_file" "$run_id" "$status" "$error" << 'PYEOF'
import json, sys, time

ledger_file, run_id, status, error = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

try:
    with open(ledger_file) as f:
        ledger = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    ledger = {"runs": []}

ledger["runs"].append({
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "run_id": run_id,
    "status": status,
    "error": error[:200] if error else ""
})

# Keep only last 100 runs
if len(ledger["runs"]) > 100:
    ledger["runs"] = ledger["runs"][-100:]

with open(ledger_file, "w") as f:
    json.dump(ledger, f, indent=2)

print(f"Recorded: {run_id} = {status}")
PYEOF
}

# ── Memory ────────────────────────────────────────────────────────────────
memory_set() {
  local key="${1:-}"
  local value="${2:-}"
  
  python3 - "$MEMORY_FILE" "$key" "$value" << 'PYEOF'
import json, sys, time

memory_file, key, value = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(memory_file) as f:
        memory = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    memory = {}

memory[key] = {
    "value": value,
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
}

with open(memory_file, "w") as f:
    json.dump(memory, f, indent=2)

print(f"Memory saved: {key}")
PYEOF
}

memory_get() {
  local key="${1:-}"
  
  python3 - "$MEMORY_FILE" "$key" << 'PYEOF'
import json, sys

memory_file, key = sys.argv[1], sys.argv[2]

try:
    with open(memory_file) as f:
        memory = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print("No memory found")
    sys.exit(1)

if key in memory:
    entry = memory[key]
    print(f"{key}: {entry.get('value', '?')} ({entry.get('ts', '?')[:10]})")
else:
    available = list(memory.keys())[:10]
    print(f"Key '{key}' not found")
    if available:
        print(f"Available: {', '.join(available)}")
    sys.exit(1)
PYEOF
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-help}" in
  check)
    shift
    LEDGER="${DATA_DIR}/loop-ledger.json"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --ledger) LEDGER="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    check_circuit "$LEDGER"
    ;;
  record)
    shift
    LEDGER="${DATA_DIR}/loop-ledger.json"
    RUN_ID=""
    STATUS="ok"
    ERROR=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --ledger) LEDGER="$2"; shift 2 ;;
        --run-id) RUN_ID="$2"; shift 2 ;;
        --status) STATUS="$2"; shift 2 ;;
        --error) ERROR="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    record_run "$LEDGER" "$RUN_ID" "$STATUS" "$ERROR"
    ;;
  memory)
    shift
    KEY=""
    VALUE=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --key) KEY="$2"; shift 2 ;;
        --value) VALUE="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    memory_set "$KEY" "$VALUE"
    ;;
  memory-get)
    shift
    KEY="${1:-}"
    memory_get "$KEY"
    ;;
  *)
    echo "Usage: bash tools/loop-context.sh {check|record|memory|memory-get}"
    ;;
esac
