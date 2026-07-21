#!/usr/bin/env bash
# integrations/graphiti/graphiti-adapter.sh
# Graphiti Temporal Knowledge Graph Adapter for MCF
#
# Provides graph-based memory for MCF agents
# Replaces flat-file memory (MEMORY.md) with temporal knowledge graph
#
# Usage:
#   bash graphiti-adapter.sh init
#   bash graphiti-adapter.sh add-episode "text" "source"
#   bash graphiti-adapter.sh search "query"
#   bash graphiti-adapter.sh get-entity "name"
#   bash graphiti-adapter.sh timeline "entity"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/.data"
export GRAPHITI_DB_PATH="${DATA_DIR}/graphiti.db"

mkdir -p "$DATA_DIR"

# ── Initialize Graphiti ──────────────────────────────────────────────────
init_graphiti() {
  echo "Initializing Graphiti temporal knowledge graph..."
  
  # Check dependencies
  if ! python3 -c "import graphiti_core" 2>/dev/null; then
    echo "Installing graphiti-core..."
    pip install graphiti-core 2>/dev/null || pip3 install graphiti-core 2>/dev/null
  fi
  
  python3 - "$DATA_DIR" << 'PYEOF'
import sys, os
data_dir = sys.argv[1]
os.makedirs(data_dir, exist_ok=True)

# Create local graph storage
graph_db = os.path.join(data_dir, "graph.json")
if not os.path.exists(graph_db):
    import json
    with open(graph_db, "w") as f:
        json.dump({"entities": {}, "edges": {}, "episodes": []}, f)
    print(f"✅ Created graph database: {graph_db}")
else:
    print(f"✅ Graph database exists: {graph_db}")
PYEOF

  echo "✅ Graphiti initialized at ${DATA_DIR}"
}

# ── Add Episode (fact/event) ─────────────────────────────────────────────
add_episode() {
  local text="${1:-}"
  local source="${2:-mcf}"
  
  [[ -z "$text" ]] && { echo "Usage: add-episode <text> [source]"; return 1; }
  
  python3 - "$text" "$source" "$DATA_DIR" << 'PYEOF'
import sys, json, os, time
from datetime import datetime

text, source, data_dir = sys.argv[1], sys.argv[2], sys.argv[3]
graph_db = os.path.join(data_dir, "graph.json")

with open(graph_db) as f:
    graph = json.load(f)

episode = {
    "id": f"ep-{int(time.time() * 1000)}",
    "text": text,
    "source": source,
    "timestamp": datetime.utcnow().isoformat() + "Z",
    "entities": []
}

# Simple entity extraction (capitalized words as entities)
import re
entities = set(re.findall(r'\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b', text))
episode["entities"] = list(entities)

# Add entities to graph
for entity in entities:
    if entity not in graph["entities"]:
        graph["entities"][entity] = {
            "name": entity,
            "mentions": 0,
            "first_seen": episode["timestamp"],
            "last_seen": episode["timestamp"]
        }
    graph["entities"][entity]["mentions"] += 1
    graph["entities"][entity]["last_seen"] = episode["timestamp"]

# Add episode
graph["episodes"].append(episode)

with open(graph_db, "w") as f:
    json.dump(graph, f, indent=2)

print(f"✅ Added episode: {episode['id']}")
print(f"   Entities: {', '.join(entities) if entities else 'none'}")
PYEOF
}

# ── Search ────────────────────────────────────────────────────────────────
search_graph() {
  local query="${1:-}"
  
  [[ -z "$query" ]] && { echo "Usage: search <query>"; return 1; }
  
  python3 - "$query" "$DATA_DIR" << 'PYEOF'
import sys, json, os

query, data_dir = sys.argv[1], sys.argv[2]
graph_db = os.path.join(data_dir, "graph.json")

if not os.path.exists(graph_db):
    print("❌ Graph not initialized. Run: bash graphiti-adapter.sh init")
    sys.exit(1)

with open(graph_db) as f:
    graph = json.load(f)

query_lower = query.lower()
results = []

# Search episodes
for ep in graph.get("episodes", []):
    score = 0
    text_lower = ep.get("text", "").lower()
    for word in query_lower.split():
        if word in text_lower:
            score += 1
    if score > 0:
        results.append({
            "type": "episode",
            "id": ep.get("id"),
            "text": ep.get("text", "")[:100],
            "score": score,
            "timestamp": ep.get("timestamp")
        })

# Search entities
for name, entity in graph.get("entities", {}).items():
    if any(word in name.lower() for word in query_lower.split()):
        results.append({
            "type": "entity",
            "name": name,
            "mentions": entity.get("mentions", 0),
            "score": entity.get("mentions", 0)
        })

# Sort by score
results.sort(key=lambda x: x.get("score", 0), reverse=True)

if results:
    print(f"Found {len(results)} results for '{query}':")
    for r in results[:10]:
        if r["type"] == "episode":
            print(f"  📄 {r['text'][:60]}... ({r['timestamp'][:10]})")
        else:
            print(f"  🔵 {r['name']} ({r['mentions']} mentions)")
else:
    print(f"No results for '{query}'")
PYEOF
}

# ── Get Entity Timeline ──────────────────────────────────────────────────
get_entity() {
  local entity_name="${1:-}"
  
  [[ -z "$entity_name" ]] && { echo "Usage: get-entity <name>"; return 1; }
  
  python3 - "$entity_name" "$DATA_DIR" << 'PYEOF'
import sys, json, os

name, data_dir = sys.argv[1], sys.argv[2]
graph_db = os.path.join(data_dir, "graph.json")

with open(graph_db) as f:
    graph = json.load(f)

# Find entity
entity = graph.get("entities", {}).get(name)
if not entity:
    print(f"❌ Entity '{name}' not found")
    sys.exit(1)

print(f"🔵 {name}")
print(f"   Mentions: {entity.get('mentions', 0)}")
print(f"   First seen: {entity.get('first_seen', 'unknown')}")
print(f"   Last seen: {entity.get('last_seen', 'unknown')}")

# Find related episodes
print(f"   Related episodes:")
for ep in graph.get("episodes", []):
    if name in ep.get("entities", []):
        print(f"     📄 {ep.get('text', '')[:60]}... ({ep.get('timestamp', '')[:10]})")
PYEOF
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-help}" in
  init)           init_graphiti ;;
  add-episode)    shift; add_episode "$@" ;;
  search)         shift; search_graph "$@" ;;
  get-entity)     shift; get_entity "$@" ;;
  *)
    echo "Usage: bash graphiti-adapter.sh {init|add-episode|search|get-entity}"
    ;;
esac
