#!/usr/bin/env bash
# integrations/graph-engineering/graph-workflow.sh
# Graph Workflow Engine for MCF
#
# Based on 0xCodez "Graph Engineering with Claude: 14-Step Roadmap"
# Core concept: Nodes are jobs, Edges are dependencies
# Linear → Graph transformation for parallel execution
#
# Usage:
#   bash graph-workflow.sh run <workflow.yaml>
#   bash graph-workflow.sh visualize <workflow.yaml>
#   bash graph-workflow.sh validate <workflow.yaml>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_FILE="${2:-}"

# ── Core: Parse workflow DAG ──────────────────────────────────────────────
parse_workflow() {
  python3 - "$WORKFLOW_FILE" << 'PYEOF'
import yaml, sys, json

with open(sys.argv[1]) as f:
    workflow = yaml.safe_load(f)

nodes = workflow.get('nodes', [])
edges = workflow.get('edges', [])

# Build adjacency list
graph = {node['id']: [] for node in nodes}
in_degree = {node['id']: 0 for node in nodes}

for edge in edges:
    from_id = edge.get('from', edge.get('source'))
    to_id = edge.get('to', edge.get('target'))
    if from_id in graph:
        graph[from_id].append(to_id)
        in_degree[to_id] = in_degree.get(to_id, 0) + 1

# Topological sort for execution order (Kahn's algorithm)
execution_order = []
queue = [n for n, d in in_degree.items() if d == 0]

while queue:
    level = []
    next_queue = []
    for node_id in queue:
        level.append(node_id)
        for neighbor in graph.get(node_id, []):
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                next_queue.append(neighbor)
    execution_order.append(level)
    queue = next_queue

print(json.dumps({
    'nodes': len(nodes),
    'edges': len(edges),
    'levels': execution_order,
    'parallelism': max(len(level) for level in execution_order) if execution_order else 0
}))
PYEOF
}

# ── Core: Execute workflow ────────────────────────────────────────────────
execute_workflow() {
  echo "═══════════════════════════════════════════"
  echo "  Graph Workflow Engine"
  echo "═══════════════════════════════════════════"
  echo ""
  
  local analysis
  analysis=$(parse_workflow)
  
  local levels
  levels=$(echo "$analysis" | python3 -c "import json,sys;d=json.load(sys.stdin);print(len(d['levels']))")
  local parallelism
  parallelism=$(echo "$analysis" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['parallelism'])")
  
  echo "Workflow analysis:"
  echo "  Nodes: $(echo "$analysis" | python3 -c "import json,sys;print(json.load(sys.stdin)['nodes'])")"
  echo "  Edges: $(echo "$analysis" | python3 -c "import json,sys;print(json.load(sys.stdin)['edges'])")"
  echo "  Execution levels: $levels"
  echo "  Max parallelism: $parallelism"
  echo ""
  
  # Execute level by level
  python3 - "$WORKFLOW_FILE" << 'PYEOF'
import yaml, sys, subprocess, json, concurrent.futures

with open(sys.argv[1]) as f:
    workflow = yaml.safe_load(f)

nodes = {n['id']: n for n in workflow.get('nodes', [])}
edges = workflow.get('edges', [])

# Build dependency graph
graph = {node_id: [] for node_id in nodes}
in_degree = {node_id: 0 for node_id in nodes}

for edge in edges:
    from_id = edge.get('from', edge.get('source'))
    to_id = edge.get('to', edge.get('target'))
    if from_id in graph:
        graph[from_id].append(to_id)
        in_degree[to_id] = in_degree.get(to_id, 0) + 1

# Execute levels
execution_log = []
queue = [n for n, d in in_degree.items() if d == 0]
level_num = 0

while queue:
    level_num += 1
    print(f"── Level {level_num} ({len(queue)} nodes) ──")
    
    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(queue)) as executor:
        futures = {}
        for node_id in queue:
            node = nodes[node_id]
            command = node.get('command', 'echo no-op')
            futures[executor.submit(subprocess.run, command, shell=True, capture_output=True, timeout=300)] = node_id
        
        for future in concurrent.futures.as_completed(futures):
            node_id = futures[future]
            try:
                result = future.result()
                status = "✅" if result.returncode == 0 else "❌"
                print(f"  {status} {node_id}: {result.returncode}")
                results[node_id] = result.returncode
            except Exception as e:
                print(f"  ❌ {node_id}: {e}")
                results[node_id] = 1
    
    # Next level
    next_queue = []
    for node_id in queue:
        for neighbor in graph.get(node_id, []):
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                next_queue.append(neighbor)
    queue = next_queue
    execution_log.append({"level": level_num, "nodes": list(results.keys())})

print("")
print("✅ Workflow complete")
PYEOF
}

# ── Visualize workflow as Mermaid diagram ────────────────────────────────
visualize_workflow() {
  python3 - "$WORKFLOW_FILE" << 'PYEOF'
import yaml, sys

with open(sys.argv[1]) as f:
    workflow = yaml.safe_load(f)

print("```mermaid")
print("flowchart TD")

for node in workflow.get('nodes', []):
    node_id = node['id']
    label = node.get('label', node_id)
    print(f"    {node_id}[{label}]")

for edge in workflow.get('edges', []):
    from_id = edge.get('from', edge.get('source'))
    to_id = edge.get('to', edge.get('target'))
    label = edge.get('label', '')
    if label:
        print(f"    {from_id} -->|{label}| {to_id}")
    else:
        print(f"    {from_id} --> {to_id}")

print("```")
PYEOF
}

# ── Validate workflow ─────────────────────────────────────────────────────
validate_workflow() {
  python3 - "$WORKFLOW_FILE" << 'PYEOF'
import yaml, sys

errors = []
with open(sys.argv[1]) as f:
    workflow = yaml.safe_load(f)

nodes = workflow.get('nodes', [])
edges = workflow.get('edges', [])
node_ids = {n['id'] for n in nodes}

# Check for missing node references
for edge in edges:
    from_id = edge.get('from', edge.get('source'))
    to_id = edge.get('to', edge.get('target'))
    if from_id not in node_ids:
        errors.append(f"Edge references unknown node: {from_id}")
    if to_id not in node_ids:
        errors.append(f"Edge references unknown node: {to_id}")

# Check for cycles (DFS)
graph = {n['id']: [] for n in nodes}
for edge in edges:
    from_id = edge.get('from', edge.get('source'))
    to_id = edge.get('to', edge.get('target'))
    if from_id in graph:
        graph[from_id].append(to_id)

visited = set()
rec_stack = set()

def has_cycle(node):
    visited.add(node)
    rec_stack.add(node)
    for neighbor in graph.get(node, []):
        if neighbor not in visited:
            if has_cycle(neighbor):
                return True
        elif neighbor in rec_stack:
            return True
    rec_stack.remove(node)
    return False

for node_id in node_ids:
    if node_id not in visited:
        if has_cycle(node_id):
            errors.append("Workflow contains cycles (must be a DAG)")

if errors:
    print("❌ Validation failed:")
    for e in errors:
        print(f"  - {e}")
    sys.exit(1)
else:
    print("✅ Workflow is valid DAG")
PYEOF
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-help}" in
  run)        execute_workflow ;;
  visualize)  visualize_workflow ;;
  validate)  validate_workflow ;;
  parse)      parse_workflow ;;
  *)
    echo "Usage: bash graph-workflow.sh {run|visualize|validate|parse} <workflow.yaml>"
    echo ""
    echo "Example workflow.yaml:"
    echo "  nodes:"
    echo "    - id: scan-ci"
    echo "      command: bash scripts/check-ci.sh"
    echo "    - id: triage"
    echo "      command: bash scripts/triage.sh"
    echo "  edges:"
    echo "    - from: scan-ci"
    echo "      to: triage"
    ;;
esac
