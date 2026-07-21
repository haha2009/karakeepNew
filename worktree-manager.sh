#!/usr/bin/env bash
# worktree-manager.sh — Git worktree isolation for parallel sub-agents
# Prevents file collisions when running multiple agents simultaneously.
#
# Reference: 0xCodez "Worktrees: parallel without chaos"
# Reference: ArchiveExplorer "Sub-agent fan-out"
#
# Usage:
#   worktree-manager.sh create <agent-name>   # Create isolated worktree
#   worktree-manager.sh list                  # List active worktrees
#   worktree-manager.sh destroy <agent-name>  # Remove worktree
#   worktree-manager.sh destroy-all           # Clean up all MCF worktrees
#   worktree-manager.sh status                # Show status

set -uo pipefail

FWK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE_BASE="${FWK_DIR}/.worktrees"
STATE_FILE="${FWK_DIR}/.memory/.worktree-state.json"

mkdir -p "$WORKTREE_BASE"

# ── Create ──────────────────────────────────────────────────────────────────
create_worktree() {
  local agent_name="${1:-agent}"
  # Validate agent_name: only alphanumeric, underscore, hyphen
  if [[ ! "$agent_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "❌ Invalid agent_name: only [a-zA-Z0-9_-] allowed" >&2
    return 1
  fi
  local branch_name="mcf-agent-$(date +%Y%m%d-%H%M%S)-${agent_name}"
  local worktree_path="${WORKTREE_BASE}/${agent_name}"
  
  # Check if already exists
  if [[ -d "$worktree_path" ]]; then
    echo "⚠️  Worktree already exists: ${worktree_path}"
    echo "   Destroy first or use a different name."
    return 1
  fi
  
  # Create worktree with new branch from current HEAD
  if git -C "$FWK_DIR" worktree add "$worktree_path" -b "$branch_name" 2>/dev/null; then
    echo "✅ Worktree created: ${worktree_path}"
    echo "   Branch: ${branch_name}"
    echo "   Agent: ${agent_name}"
    
    # Record in state
    python3 - "$STATE_FILE" "$agent_name" "$worktree_path" "$branch_name" << 'PYEOF'
import json, sys, time, os
state_file, name, path, branch = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
state = {"worktrees": []}
if os.path.exists(state_file):
    state = json.load(open(state_file))
state["worktrees"].append({
    "name": name,
    "path": path,
    "branch": branch,
    "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "status": "active"
})
json.dump(state, open(state_file, "w"), indent=2)
PYEOF
    
    echo ""
    echo "To use in Claude Code:"
    echo "  cd ${worktree_path}"
    echo "  # Run agent work here"
    echo ""
    echo "To merge back:"
    echo "  git -C ${FWK_DIR} merge ${branch_name}"
    echo "  bash ${FWK_DIR}/worktree-manager.sh destroy ${agent_name}"
  else
    echo "❌ Failed to create worktree"
    return 1
  fi
}

# ── List ────────────────────────────────────────────────────────────────────
list_worktrees() {
  echo "═══ Active Worktrees ═══"
  echo ""
  git -C "$FWK_DIR" worktree list | grep -v "^${FWK_DIR} " | while IFS= read -r line; do
    echo "  $line"
  done
  echo ""
  
  if [[ -f "$STATE_FILE" ]]; then
    python3 - "$STATE_FILE" << 'PYEOF'
import json, sys, os
state = json.load(open(sys.argv[1]))
wt = state.get("worktrees", [])
active = [w for w in wt if w.get("status") == "active"]
print(f"Tracked: {len(active)} active worktree(s)")
for w in active:
    print(f"  - {w['name']}: {w['branch']} ({w['created_at'][:10]})")
PYEOF
  fi
}

# ── Destroy ─────────────────────────────────────────────────────────────────
destroy_worktree() {
  local agent_name="${1:-}"
  [[ -z "$agent_name" ]] && { echo "Usage: worktree-manager.sh destroy <agent-name>"; return 1; }
  
  local worktree_path="${WORKTREE_BASE}/${agent_name}"
  
  if [[ ! -d "$worktree_path" ]]; then
    echo "⚠️  Worktree not found: ${worktree_path}"
    return 1
  fi
  
  # Get branch name before removing
  local branch
  branch=$(git -C "$worktree_path" branch --show-current 2>/dev/null || echo "unknown")
  
  # Remove worktree
  git -C "$FWK_DIR" worktree remove "$worktree_path" --force 2>/dev/null
  # Clean up orphan branch
  if [[ "$branch" != "unknown" ]]; then
    git -C "$FWK_DIR" branch -d "$branch" 2>/dev/null || true
  fi
  
  # Update state
  python3 - "$STATE_FILE" "$agent_name" << 'PYEOF'
import json, sys, os, time
state_file, name = sys.argv[1], sys.argv[2]
if os.path.exists(state_file):
    state = json.load(open(state_file))
    for w in state.get("worktrees", []):
        if w.get("name") == name:
            w["status"] = "destroyed"
            w["destroyed_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    json.dump(state, open(state_file, "w"), indent=2)
PYEOF
  
  echo "✅ Worktree destroyed: ${agent_name} (branch: ${branch})"
  echo "   Remember to merge changes before destroying if needed:"
  echo "   git -C ${FWK_DIR} merge ${branch}"
}

# ── Destroy All ─────────────────────────────────────────────────────────────
destroy_all() {
  echo "Destroying all MCF worktrees..."
  if [[ -f "$STATE_FILE" ]]; then
    python3 - "$STATE_FILE" << 'PYEOF'
import json, sys, os
state = json.load(open(sys.argv[1]))
for w in state.get("worktrees", []):
    if w.get("status") == "active":
        print(w["name"])
PYEOF
  fi | while IFS= read -r name; do
    destroy_worktree "$name"
  done
  echo "✅ All worktrees cleaned up"
}

# ── Status ──────────────────────────────────────────────────────────────────
status() {
  echo "═══ Worktree Manager Status ═══"
  echo "Base: ${WORKTREE_BASE}"
  echo ""
  list_worktrees
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-status}" in
  create)       shift; create_worktree "${1:-agent}" ;;
  list)         list_worktrees ;;
  destroy)      shift; destroy_worktree "${1:-}" ;;
  destroy-all)  destroy_all ;;
  status)       status ;;
  *)            echo "Usage: worktree-manager.sh {create <name>|list|destroy <name>|destroy-all|status}" ;;
esac
