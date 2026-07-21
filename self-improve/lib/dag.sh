#!/usr/bin/env bash
# self-improve/lib/dag.sh
# DAG executor - bash 3.2 compatible (no associative arrays)
# Uses parallel indexed arrays instead of declare -A

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_IMPROVE_DIR="$(dirname "$SCRIPT_DIR")"
MEMORY_DIR="${SELF_IMPROVE_DIR}/.memory"

# ── Node storage (parallel arrays, bash 3.2 compatible) ──────────
NODE_IDS=()
NODE_NAMES=()
NODE_SCRIPTS=()
NODE_DEPS=()
NODE_STATUS=()  # pending | running | done | failed

init_dag() {
  NODE_IDS=()
  NODE_NAMES=()
  NODE_SCRIPTS=()
  NODE_DEPS=()
  NODE_STATUS=()
}

# Register a node
node() {
  local id="$1" name="$2" script="$3" deps="$4"
  NODE_IDS+=("$id")
  NODE_NAMES+=("$name")
  NODE_SCRIPTS+=("$script")
  NODE_DEPS+=("$deps")
  NODE_STATUS+=("pending")
}

# Find index of node by id
_node_idx() {
  local id="$1"
  for i in "${!NODE_IDS[@]}"; do
    [[ "${NODE_IDS[$i]}" == "$id" ]] && echo "$i" && return 0
  done
  echo "-1"
}

# Check if all dependencies are satisfied
deps_satisfied() {
  local idx="$1"
  local deps="${NODE_DEPS[$idx]}"
  [[ -z "$deps" ]] && return 0
  
  local IFS=','
  for dep in $deps; do
    local dep_idx; dep_idx=$(_node_idx "$dep")
    [[ "${NODE_STATUS[$dep_idx]}" == "done" ]] || return 1
  done
  return 0
}

# ── Mermaid visualization ────────────────────────────────────────
mermaid_dag() {
  echo "graph TD"
  for i in "${!NODE_IDS[@]}"; do
    echo "    ${NODE_IDS[$i]}[${NODE_NAMES[$i]}]"
  done
  for i in "${!NODE_IDS[@]}"; do
    local deps="${NODE_DEPS[$i]}"
    if [[ -n "$deps" ]]; then
      local IFS=','
      for dep in $deps; do
        echo "    $dep --> ${NODE_IDS[$i]}"
      done
    fi
  done
}

case "${1:-}" in
  mermaid) mermaid_dag ;;
  *) echo "Usage: dag.sh mermaid" ;;
esac
