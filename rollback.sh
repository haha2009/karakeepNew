#!/usr/bin/env bash
# rollback.sh — Rollback mechanism for MCF Framework
#
# Reference: Bot audit "No rollback mechanism" + my verification
# Saves state before changes, allows restore on failure
#
# v1.4: Simple git-based + snapshot rollback

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FWK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MEMORY_DIR="${FWK_DIR}/.memory"
ROLLBACK_DIR="${MEMORY_DIR}/.rollback"
MAX_SNAPSHOTS=10

mkdir -p "$ROLLBACK_DIR"

# ── Save current state ────────────────────────────────────────────────────
save_snapshot() {
  local reason="${1:-manual}"
  local ts
  ts=$(date +%Y%m%d_%H%M%S)
  local snapshot_dir="${ROLLBACK_DIR}/${ts}"
  mkdir -p "$snapshot_dir"
  
  # Save git state
  if git -C "$FWK_DIR" rev-parse HEAD &>/dev/null; then
    git -C "$FWK_DIR" rev-parse HEAD > "${snapshot_dir}/git-commit.txt"
    git -C "$FWK_DIR" status --short > "${snapshot_dir}/git-status.txt"
  fi
  
  # Save health score
  if [[ -f "${MEMORY_DIR}/.health-score.json" ]]; then
    cp "${MEMORY_DIR}/.health-score.json" "${snapshot_dir}/"
  fi
  
  # Save loop state
  if [[ -f "${MEMORY_DIR}/.loop-state.json" ]]; then
    cp "${MEMORY_DIR}/.loop-state.json" "${snapshot_dir}/"
  fi
  
  # Save reason
  echo "$reason" > "${snapshot_dir}/reason.txt"
  
  # Cleanup old snapshots
  local count
  count=$(ls -1d "${ROLLBACK_DIR}"/*/ 2>/dev/null | wc -l)
  if [[ $count -gt $MAX_SNAPSHOTS ]]; then
    ls -1d "${ROLLBACK_DIR}"/*/ 2>/dev/null | head -n $((count - MAX_SNAPSHOTS)) | xargs rm -rf
  fi
  
  echo "✅ Snapshot saved: ${ts}"
  echo "   Reason: ${reason}"
}

# ── List available snapshots ──────────────────────────────────────────────
list_snapshots() {
  echo "═══ Available Rollback Snapshots ═══"
  
  if [[ ! -d "$ROLLBACK_DIR" ]] || [[ -z "$(ls -A "$ROLLBACK_DIR" 2>/dev/null)" ]]; then
    echo "  No snapshots available"
    return
  fi
  
  for snapshot in $(ls -1rd "${ROLLBACK_DIR}"/*/ 2>/dev/null); do
    local ts
    ts=$(basename "$snapshot")
    local reason
    reason=$(cat "${snapshot}/reason.txt" 2>/dev/null || echo "unknown")
    local commit
    commit=$(cat "${snapshot}/git-commit.txt" 2>/dev/null | cut -c1-8 || echo "n/a")
    echo "  ${ts} | commit: ${commit} | reason: ${reason}"
  done
}

# ── Restore from snapshot ────────────────────────────────────────────────
rollback() {
  local ts="$1"
  if [[ -z "$ts" ]]; then
    echo "Usage: rollback.sh restore <timestamp>"
    echo "Run 'rollback.sh list' to see available snapshots"
    return 1
  fi
  
  local snapshot_dir="${ROLLBACK_DIR}/${ts}"
  if [[ ! -d "$snapshot_dir" ]]; then
    echo "❌ Snapshot not found: ${ts}"
    return 1
  fi
  
  echo "⚠️  Rolling back to: ${ts}"
  echo "   Reason: $(cat "${snapshot_dir}/reason.txt" 2>/dev/null)"
  echo ""
  
  # Confirm
  read -p "Confirm rollback? This will reset files to snapshot state. [Y/N]: " CONFIRM
  [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && { echo "Cancelled"; return 0; }
  
  # Restore git state
  if [[ -f "${snapshot_dir}/git-commit.txt" ]]; then
    local commit
    commit=$(cat "${snapshot_dir}/git-commit.txt")
    echo "   Restoring git to: ${commit}"
    git -C "$FWK_DIR" checkout "$commit" -- . 2>/dev/null || echo "   ⚠️  Git restore failed"
  fi
  
  # Restore health score
  if [[ -f "${snapshot_dir}/.health-score.json" ]]; then
    cp "${snapshot_dir}/.health-score.json" "${MEMORY_DIR}/"
    echo "   ✅ Health score restored"
  fi
  
  # Restore loop state
  if [[ -f "${snapshot_dir}/.loop-state.json" ]]; then
    cp "${snapshot_dir}/.loop-state.json" "${MEMORY_DIR}/"
    echo "   ✅ Loop state restored"
  fi
  
  echo ""
  echo "✅ Rollback complete"
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-list}" in
  save)       shift; save_snapshot "$@" ;;
  list)       list_snapshots ;;
  restore)    shift; rollback "$@" ;;
  *)          echo "Usage: rollback.sh {save|list|restore <timestamp>}" ;;
esac
