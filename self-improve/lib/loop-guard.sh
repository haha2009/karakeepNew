#!/usr/bin/env bash
# self-improve/lib/loop-guard.sh
# Ralph Wiggum detection + Context rot protection
# Prevents: repeated iterations, unbounded context growth, silent drift
#
# Reference: ArchiveExplorer "Loop and Harness engineering" (2026-06-28)
# Reference: 0xCodez "14-step roadmap" (2026-06-09)
#
# v1.4 fix: A3 - portable locking(macOS + Linux)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/safety.sh"
FWK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MEMORY_DIR="${FWK_DIR}/.memory"
STATE_FILE="${MEMORY_DIR}/.loop-state.json"

# ── Thresholds ──────────────────────────────────────────────────────────────
MAX_ITERATIONS=10
MAX_TOKEN_ESTIMATE=40000
REPEAT_WINDOW=3
MIN_PROGRESS_EVENTS=1

# ── Portable Locking(macOS + Linux) ──────────────────────────────────────────
_lock() {
  local lock_file="$1"
  if command -v flock &>/dev/null; then
    flock -x 200 || { echo "DRIFT: cannot acquire lock" >&2; return 1; }
  else
    # macOS fallback: mkdir is atomic
    local tries=0
    while ! mkdir "${lock_file}.dir" 2>/dev/null; do
      tries=$((tries + 1))
      [[ $tries -gt 50 ]] && { echo "DRIFT: lock timeout" >&2; return 1; }
      sleep 0.1
    done
  fi
}

_unlock() {
  local lock_file="$1"
  if ! command -v flock &>/dev/null; then
    rmdir "${lock_file}.dir" 2>/dev/null || true
  fi
}

# ── State initialization ─────────────────────────────────────────────────────
init_state() {
  mkdir -p "$MEMORY_DIR"
  [[ ! -f "$STATE_FILE" ]] || return 0
  echo '{"iterations":[],"total_tokens":0,"started_at":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","status":"running"}' > "$STATE_FILE"
}

# ── Ralph Wiggum Detection ──────────────────────────────────────────────────
record_iteration() {
  local action_sig="$1"
  local tokens_used="${2:-1000}"
  
  init_state
  local lock_file="${STATE_FILE}.lock"
  
  _lock "$lock_file"
  
  python3 - "$STATE_FILE" "$action_sig" "$tokens_used" << 'PYEOF'
import json, sys, time
state_file, action_sig, tokens_used = sys.argv[1], sys.argv[2], int(sys.argv[3])
state = json.load(open(state_file))
state["iterations"].append({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "action_sig": action_sig, "tokens": tokens_used})
state["total_tokens"] = state.get("total_tokens", 0) + tokens_used
state["iterations"] = state["iterations"][-10:]
window = state["iterations"][-3:]
if len(window) >= 3:
    sigs = [it["action_sig"] for it in window]
    if len(set(sigs)) == 1:
        state["status"] = "ralph_wiggum_detected"
        state["ralph_reason"] = f"Same action signature repeated 3x"
    elif len(set(sigs)) <= len(sigs) // 2:
        state["status"] = "possible_drift"
        state["drift_reason"] = "Majority of recent iterations share signatures"
json.dump(state, open(state_file, "w"), indent=2)
status = state.get("status", "running")
if status == "ralph_wiggum_detected":
    print("RALPH_WIGGUM")
    sys.exit(2)
elif status == "possible_drift":
    print("POSSIBLE_DRIFT")
    sys.exit(1)
else:
    print("PROGRESS_OK")
    sys.exit(0)
PYEOF
  
  _unlock "$lock_file"
}

# ── Context Rot Protection ──────────────────────────────────────────────────
check_context_rot() {
  local current_tokens="${1:-0}"
  
  init_state
  local lock_file="${STATE_FILE}.lock"
  
  _lock "$lock_file"
  
  python3 - "$STATE_FILE" "$current_tokens" << 'PYEOF'
import json, sys
state_file, current_tokens = sys.argv[1], int(sys.argv[2])
state = json.load(open(state_file))
total = state.get("total_tokens", 0) + current_tokens
iterations = len(state.get("iterations", []))
if iterations >= 10:
    print("HARD_STOP: max iterations (10) reached")
    sys.exit(2)
if total >= 40000:
    print("HARD_STOP: token budget exhausted")
    sys.exit(2)
if total >= 30000:
    print("SOFT_WARNING: approaching token limit")
    sys.exit(1)
if iterations >= 7:
    print("SOFT_WARNING: approaching iteration limit")
    sys.exit(1)
if iterations >= 5:
    recent = state["iterations"][-5:]
    unique_sigs = len(set(it["action_sig"] for it in recent))
    if unique_sigs <= 2:
        print("CONTEXT_ROT_SYMPTOM: low action diversity")
        sys.exit(2)
print("HEALTHY")
sys.exit(0)
PYEOF
  
  _unlock "$lock_file"
}

# ── Compressed State Handoff ────────────────────────────────────────────────
write_checkpoint() {
  local reason="${1:-scheduled}"
  
  init_state
  local lock_file="${STATE_FILE}.lock"
  
  _lock "$lock_file"
  
  python3 - "$STATE_FILE" "$reason" << 'PYEOF'
import json, sys, time
state_file, reason = sys.argv[1], sys.argv[2]
state = json.load(open(state_file))
iterations = state.get("iterations", [])
checkpoint = {
    "exited_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "reason": reason,
    "iterations_run": len(iterations),
    "total_tokens": state.get("total_tokens", 0),
    "status": "checkpointed"
}
checkpoint_file = state_file.replace(".loop-state.json", ".checkpoint.json")
json.dump(checkpoint, open(checkpoint_file, "w"), indent=2)
state["iterations"] = []
state["total_tokens"] = 0
state["started_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
state["status"] = "running"
json.dump(state, open(state_file, "w"), indent=2)
print(f"CHECKPOINT_WRITTEN: {checkpoint_file}")
PYEOF
  
  _unlock "$lock_file"
}

# ── Report ─────────────────────────────────────────────────────────────────
report() {
  init_state
  python3 - "$STATE_FILE" << 'PYEOF'
import json, sys
state = json.load(open(sys.argv[1]))
print(f"Loop State: {state.get('status', 'unknown')}")
print(f"Iterations: {len(state.get('iterations', []))}/10")
print(f"Total tokens: {state.get('total_tokens', 0)}/40000")
PYEOF
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-report}" in
  record) shift; record_iteration "$@" ;;
  check) shift; check_context_rot "$@" ;;
  checkpoint) shift; write_checkpoint "$@" ;;
  *) report ;;
esac
