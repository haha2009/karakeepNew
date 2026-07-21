#!/usr/bin/env bash
# self-improve/lib/human-loop.sh
# Human-in-the-Loop pattern
#
# Reference: Gulli "Agentic Design Patterns" Ch.13 — Human-in-the-Loop
# Key decision points pause for human approval/rejection before proceeding.
# Risk levels: LOW (auto), MEDIUM (notify), HIGH (require approval), CRITICAL (block)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FWK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MEMORY_DIR="${FWK_DIR}/.memory"
APPROVAL_FILE="${MEMORY_DIR}/.approval-request.json"
APPROVAL_LOG="${MEMORY_DIR}/.approval-log.jsonl"

# ── Risk classification ───────────────────────────────────────────────────
# Assess risk level of an operation
assess_risk() {
  local operation="$1"
  local target="$2"
  
  # CRITICAL: operations that could destroy data or compromise security
  if echo "$operation" | grep -qiE "(rm -rf|git push --force|git reset --hard|git branch -D|drop|truncate|delete.*user)"; then
    echo "CRITICAL"
    return
  fi
  
  if echo "$target" | grep -qiE "(\.claude/|\.agents/|CLAUDE\.md|AGENTS\.md|protect-framework|protect-git|\.env)"; then
    echo "CRITICAL"
    return
  fi
  
  # HIGH: operations that modify core framework or self-improve logic
  if echo "$target" | grep -qiE "(self-improve/|hooks/|safety\.sh|loop-guard\.sh|recovery\.sh|human-loop\.sh)"; then
    echo "HIGH"
    return
  fi
  
  if echo "$operation" | grep -qiE "(modify|rewrite|refactor|restructure)"; then
    echo "HIGH"
    return
  fi
  
  # MEDIUM: operations that change behavior but are reversible
  if echo "$operation" | grep -qiE "(update|change|edit|fix|patch)"; then
    echo "MEDIUM"
    return
  fi
  
  # LOW: read-only or additive operations
  echo "LOW"
}

# ── Request approval ───────────────────────────────────────────────────────
request_approval() {
  local operation="$1"
  local target="$2"
  local reason="$3"
  local risk_level
  risk_level=$(assess_risk "$operation" "$target")
  
  python3 - "$operation" "$target" "$reason" "$risk_level" "$APPROVAL_FILE" "$APPROVAL_LOG" << 'PYEOF'
import json, sys, time, os

operation, target, reason, risk_level, approval_file, approval_log = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]

request = {
    "requested_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "operation": operation,
    "target": target,
    "reason": reason,
    "risk_level": risk_level,
    "status": "pending",
    "id": f"req-{int(time.time())}"
}

# Write approval request
with open(approval_file, "w") as f:
    json.dump(request, f, indent=2)

# Append to log
with open(approval_log, "a") as f:
    f.write(json.dumps(request) + "\n")

print(f"APPROVAL_REQUIRED: {risk_level}")
print(f"  Operation: {operation}")
print(f"  Target: {target}")
print(f"  Reason: {reason}")
print(f"  Request ID: {request['id']}")
print(f"  File: {approval_file}")
print("")
print("To approve:  bash self-improve/lib/human-loop.sh approve")
print("To reject:   bash self-improve/lib/human-loop.sh reject")
PYEOF
}

# ── Check if approval is pending ───────────────────────────────────────────
check_approval_pending() {
  if [[ ! -f "$APPROVAL_FILE" ]]; then
    echo "none"
    return
  fi
  
  python3 - "$APPROVAL_FILE" << 'PYEOF'
import json, sys, os
approval_file = sys.argv[1]
if not os.path.exists(approval_file):
    print("none")
    sys.exit(0)
with open(approval_file) as f:
    req = json.load(f)
print(req.get("status", "none"))
PYEOF
}

# ── Approve pending request ────────────────────────────────────────────────
approve_request() {
  if [[ ! -f "$APPROVAL_FILE" ]]; then
    echo "No pending approval request"
    return 1
  fi
  
  python3 - "$APPROVAL_FILE" "$APPROVAL_LOG" << 'PYEOF'
import json, sys, time

approval_file, approval_log = sys.argv[1], sys.argv[2]

with open(approval_file) as f:
    req = json.load(f)

req["status"] = "approved"
req["approved_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

# Update file
with open(approval_file, "w") as f:
    json.dump(req, f, indent=2)

# Append decision to log
with open(approval_log, "a") as f:
    f.write(json.dumps({"action": "approved", **req}) + "\n")

print(f"✅ Approved: {req['operation']} on {req['target']}")
print(f"   Request ID: {req['id']}")
PYEOF
}

# ── Reject pending request ─────────────────────────────────────────────────
reject_request() {
  if [[ ! -f "$APPROVAL_FILE" ]]; then
    echo "No pending approval request"
    return 1
  fi
  
  python3 - "$APPROVAL_FILE" "$APPROVAL_LOG" << 'PYEOF'
import json, sys, time

approval_file, approval_log = sys.argv[1], sys.argv[2]

with open(approval_file) as f:
    req = json.load(f)

req["status"] = "rejected"
req["rejected_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

# Update file
with open(approval_file, "w") as f:
    json.dump(req, f, indent=2)

# Append decision to log
with open(approval_log, "a") as f:
    f.write(json.dumps({"action": "rejected", **req}) + "\n")

print(f"❌ Rejected: {req['operation']} on {req['target']}")
print(f"   Request ID: {req['id']}")
PYEOF
}

# ── Gate: check before high-risk operation ─────────────────────────────────
# Returns 0 if allowed to proceed, 1 if blocked
# Usage: human_loop_gate <operation> <target> [reason]
human_loop_gate() {
  local operation="$1"
  local target="$2"
  local reason="${3:-self-improvement automatic change}"
  
  local risk_level
  risk_level=$(assess_risk "$operation" "$target")
  
  case "$risk_level" in
    CRITICAL)
      echo "🚫 CRITICAL: Operation blocked — requires manual execution"
      echo "   ${operation} ${target}"
      request_approval "$operation" "$target" "$reason"
      return 1
      ;;
    HIGH)
      # Check if already approved
      local pending
      pending=$(check_approval_pending)
      if [[ "$pending" == "approved" ]]; then
        echo "✅ HIGH: Pre-approved — proceeding"
        return 0
      fi
      echo "⚠️  HIGH: Approval required"
      request_approval "$operation" "$target" "$reason"
      return 1
      ;;
    MEDIUM)
      echo "ℹ️  MEDIUM: ${operation} ${target} — proceeding with notification"
      return 0
      ;;
    LOW)
      # Auto-approve
      return 0
      ;;
  esac
}

# ── Status ──────────────────────────────────────────────────────────────────
human_loop_status() {
  echo "═══ Human-in-the-Loop Status ═══"
  if [[ -f "$APPROVAL_FILE" ]]; then
    python3 - "$APPROVAL_FILE" << 'PYEOF'
import json, sys, os
approval_file = sys.argv[1]
if not os.path.exists(approval_file):
    print("  No pending approvals")
    sys.exit(0)
with open(approval_file) as f:
    req = json.load(f)
status = req.get("status", "unknown")
emoji = "⏳" if status == "pending" else "✅" if status == "approved" else "❌"
print(f"  {emoji} [{req.get('risk_level', '?')}] {req.get('operation', '?')} → {req.get('target', '?')}")
print(f"     Status: {status} (ID: {req.get('id', '?')})")
PYEOF
  else
    echo "  No pending approvals"
  fi
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-status}" in
  assess)     shift; assess_risk "$@" ;;
  gate)       shift; human_loop_gate "$@" ;;
  request)    shift; request_approval "$@" ;;
  approve)    approve_request ;;
  reject)     reject_request ;;
  pending)    check_approval_pending ;;
  status)     human_loop_status ;;
  *)          echo "Usage: human-loop.sh {assess|gate <op> <target>|request|approve|reject|pending|status}" ;;
esac
