#!/usr/bin/env bash
# self-improve/lib/mcp-manager.sh (增强版)
# MCP Runtime Management + Inter-Agent Communication
# - MCP: 运行时服务器管理 + 连接池 + 健康检查
# - Inter-Agent Comm: 实时消息队列 + 发布/订阅

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FWK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MEMORY_DIR="${FWK_DIR}/.memory"
MCP_CONFIG="${FWK_DIR}/template/.mcp.json"
MCP_STATE="${MEMORY_DIR}/.mcp-state.json"
MCP_POOL="${MEMORY_DIR}/.mcp-pool"
MESSAGE_BUS="${MEMORY_DIR}/.message-bus.jsonl"

mkdir -p "$MCP_POOL"

# ═══════════════════════════════════════════════════════════════════════════
# MCP SERVER MANAGEMENT (Gulli Ch.10) — 运行时管理 + 连接池
# ═══════════════════════════════════════════════════════════════════════════

mcp_discover() {
  echo "═══ MCP Server Discovery ═══"
  
  python3 - "$MCP_CONFIG" << 'PYEOF'
import json, sys, os

mcp_config = sys.argv[1]

if not os.path.exists(mcp_config):
    print("No .mcp.json found")
    sys.exit(1)

with open(mcp_config) as f:
    config = json.load(f)

servers = config.get("mcpServers", {})
quick_start = config.get("_mcf_meta", {}).get("quick_start", {})

print(f"Configured servers: {len(servers)}")
for name, srv in servers.items():
    disabled = srv.get("disabled", False)
    status = "⚪ disabled" if disabled else "🟢 enabled"
    cmd = srv.get("command", "unknown")
    print(f"  {status} {name} ({cmd})")

print(f"\nAvailable quick-start templates: {len(quick_start)}")
for name, srv in quick_start.items():
    desc = srv.get("description", "")[:50]
    print(f"  • {name}: {desc}")

# Security audit
rules = config.get("_mcf_meta", {}).get("rules", [])
if rules:
    print(f"\nMCP Security Rules:")
    for rule in rules:
        print(f"  📋 {rule}")
PYEOF
}

mcp_validate() {
  local server_name="$1"
  
  python3 - "$server_name" "$MCP_CONFIG" << 'PYEOF'
import json, sys, os, shutil

server_name, mcp_config = sys.argv[1], sys.argv[2]

with open(mcp_config) as f:
    config = json.load(f)

servers = config.get("mcpServers", {})
quick_start = config.get("_mcf_meta", {}).get("quick_start", {})

if server_name in servers:
    srv = servers[server_name]
elif server_name in quick_start:
    srv = quick_start[server_name]
else:
    print(f"❌ Server '{server_name}' not found")
    sys.exit(1)

issues = []
warnings = []

# Check command exists
cmd = srv.get("command", "")
if cmd and not shutil.which(cmd):
    issues.append(f"Command '{cmd}' not found in PATH")

# Check required env vars
env = srv.get("env", {})
for key, value in env.items():
    if not value:
        issues.append(f"Environment variable '{key}' not set")

# Check for official sources (security)
official_sources = ["modelcontextprotocol", "github", "google"]
srv_str = json.dumps(srv)
if not any(src in srv_str for src in official_sources):
    warnings.append("Not from a known official source — verify trustworthiness")

# Validate arguments
args = srv.get("args", [])
if args:
    # Check for suspicious arguments
    suspicious = ["sudo", "rm", "curl.*|.*sh", "eval"]
    import re
    for arg in args:
        for pattern in suspicious:
            if re.search(pattern, str(arg)):
                warnings.append(f"Suspicious argument: {arg}")

if issues:
    print(f"❌ Validation FAILED for '{server_name}':")
    for issue in issues:
        print(f"  - {issue}")
    sys.exit(1)
elif warnings:
    print(f"⚠️  Validation passed with warnings for '{server_name}':")
    for warning in warnings:
        print(f"  - {warning}")
else:
    print(f"✅ '{server_name}' validation passed")
PYEOF
}

mcp_enable() {
  local server_name="$1"
  
  python3 - "$server_name" "$MCP_CONFIG" "$MCP_STATE" "$MCP_POOL" << 'PYEOF'
import json, sys, os, time, shutil

server_name, mcp_config, mcp_state, mcp_pool = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(mcp_config) as f:
    config = json.load(f)

quick_start = config.get("_mcf_meta", {}).get("quick_start", {})

if server_name in quick_start:
    config.setdefault("mCPServers", {})[server_name] = quick_start[server_name]
    print(f"✅ Enabled '{server_name}' from quick-start template")
elif server_name in config.get("mcpServers", {}):
    config["mcpServers"][server_name]["disabled"] = False
    print(f"✅ Enabled '{server_name}'")
else:
    print(f"❌ Server '{server_name}' not found")
    sys.exit(1)

with open(mcp_config, "w") as f:
    json.dump(config, f, indent=2)

# Create connection pool slot
pool_file = os.path.join(mcp_pool, f"{server_name}.json")
with open(pool_file, "w") as f:
    json.dump({
        "server": server_name,
        "enabled_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "status": "idle",
        "last_used": None,
        "total_calls": 0,
        "error_count": 0
    }, f, indent=2)

# Update state
state = {}
if os.path.exists(mcp_state):
    with open(mcp_state) as f:
        state = json.load(f)

state[server_name] = {
    "enabled_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "status": "active",
    "pool_slot": pool_file
}

with open(mcp_state, "w") as f:
    json.dump(state, f, indent=2)

print(f"  Connection pool slot created: {pool_file}")
PYEOF
}

# Health check for MCP servers
mcp_health_check() {
  local server_name="$1"
  
  python3 - "$server_name" "$MCP_POOL" << 'PYEOF'
import json, sys, os, time

server_name, mcp_pool = sys.argv[1], sys.argv[2]
pool_file = os.path.join(mcp_pool, f"{server_name}.json")

if not os.path.exists(pool_file):
    print(f"❌ No pool slot for '{server_name}'")
    sys.exit(1)

with open(pool_file) as f:
    pool = json.load(f)

# Check health
error_count = pool.get("error_count", 0)
total_calls = pool.get("total_calls", 0)
error_rate = error_count / max(total_calls, 1)

status = "healthy"
if error_rate > 0.5:
    status = "degraded"
if error_rate > 0.8:
    status = "unhealthy"

emoji = "🟢" if status == "healthy" else "🟡" if status == "degraded" else "🔴"

print(f"{emoji} {server_name}: {status}")
print(f"  Total calls: {total_calls}")
print(f"  Errors: {error_count} ({error_rate:.0%})")
print(f"  Last used: {pool.get('last_used', 'never')}")
PYEOF
}

mcp_status() {
  echo "═══ MCP Runtime Status ═══"
  
  python3 - "$MCP_STATE" "$MCP_POOL" "$MCP_CONFIG" << 'PYEOF'
import json, sys, os

mcp_state, mcp_pool, mcp_config = sys.argv[1], sys.argv[2], sys.argv[3]

# Active servers
if os.path.exists(mcp_state):
    with open(mcp_state) as f:
        state = json.load(f)
    for name, info in state.items():
        status = info.get("status", "unknown")
        emoji = "🟢" if status == "active" else "🔴"
        print(f"  {emoji} {name}: {status}")
else:
    print("  No active servers")

# Pool status
if os.path.isdir(mcp_pool):
    pool_files = [f for f in os.listdir(mcp_pool) if f.endswith(".json")]
    if pool_files:
        print(f"\nConnection Pool ({len(pool_files)} slots):")
        for pf in pool_files:
            with open(os.path.join(mcp_pool, pf)) as f:
                pool = json.load(f)
            status = pool.get("status", "unknown")
            calls = pool.get("total_calls", 0)
            print(f"  • {pool.get('server', '?')}: {status} ({calls} calls)")

# Inactive configured servers
if os.path.exists(mcp_config):
    with open(mcp_config) as f:
        config = json.load(f)
    configured = set(config.get("mcpServers", {}).keys())
    active = set()
    if os.path.exists(mcp_state):
        with open(mcp_state) as f:
            active = set(json.load(f).keys())
    inactive = configured - active
    for name in inactive:
        print(f"  ⚪ {name}: configured but inactive")
PYEOF
}

# ═══════════════════════════════════════════════════════════════════════════
# INTER-AGENT COMMUNICATION (Gulli Ch.15) — 实时消息队列
# ═══════════════════════════════════════════════════════════════════════════

msg_publish() {
  local from_agent="$1"
  local to_agent="$2"
  local msg_type="$3"
  local payload="$4"
  local priority="${5:-normal}"  # low, normal, high, urgent
  
  python3 - "$from_agent" "$to_agent" "$msg_type" "$payload" "$priority" "$MESSAGE_BUS" << 'PYEOF'
import json, sys, time

from_agent, to_agent, msg_type, payload, priority, bus = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]

message = {
    "id": f"msg-{int(time.time()*1000)}",
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "from": from_agent,
    "to": to_agent,
    "type": msg_type,
    "payload": payload[:500],
    "priority": priority,
    "status": "pending"
}

with open(bus, "a") as f:
    f.write(json.dumps(message) + "\n")

priority_emoji = {"low": "⚪", "normal": "🔵", "high": "🟡", "urgent": "🔴"}
emoji = priority_emoji.get(priority, "🔵")
print(f"{emoji} MSG: {from_agent} → {to_agent} [{msg_type}] ({priority})")
PYEOF
}

msg_consume() {
  local agent="$1"
  local max_messages="${2:-10}"
  
  python3 - "$agent" "$max_messages" "$MESSAGE_BUS" << 'PYEOF'
import json, sys, os

agent, max_messages, bus = sys.argv[1], int(sys.argv[2]), sys.argv[3]

if not os.path.exists(bus):
    print(f"No messages for {agent}")
    sys.exit(0)

messages = []
with open(bus) as f:
    for line in f:
        try:
            msg = json.loads(line.strip())
            if msg.get("to") == agent and msg.get("status") == "pending":
                messages.append(msg)
        except json.JSONDecodeError:
            continue

# Sort by priority
priority_order = {"urgent": 0, "high": 1, "normal": 2, "low": 3}
messages.sort(key=lambda m: priority_order.get(m.get("priority", "normal"), 2))

print(f"Messages for {agent}: {len(messages)}")
for msg in messages[:max_messages]:
    priority = msg.get("priority", "normal")
    emoji = {"urgent": "🔴", "high": "🟡", "normal": "🔵", "low": "⚪"}.get(priority, "🔵")
    print(f"  {emoji} [{msg['type']}] from {msg['from']}: {msg['payload'][:60]}...")
PYEOF
}

msg_process() {
  local agent="$1"
  local message_id="$2"
  
  python3 - "$agent" "$message_id" "$MESSAGE_BUS" << 'PYEOF'
import json, sys, os

agent, message_id, bus = sys.argv[1], sys.argv[2], sys.argv[3]

if not os.path.exists(bus):
    sys.exit(0)

lines = []
found = False
with open(bus) as f:
    for line in f:
        try:
            msg = json.loads(line.strip())
            if msg.get("id") == message_id and msg.get("to") == agent:
                msg["status"] = "processed"
                msg["processed_at"] = __import__("time").strftime("%Y-%m-%dT%H:%M:%SZ", __import__("time").gmtime())
                found = True
            lines.append(json.dumps(msg))
        except json.JSONDecodeError:
            continue

with open(bus, "w") as f:
    for line in lines:
        f.write(line + "\n")

if found:
    print(f"✅ Message {message_id} processed")
else:
    print(f"❌ Message {message_id} not found")
PYEOF
}

msg_status() {
  echo "═══ Message Bus Status ═══"
  
  python3 - "$MESSAGE_BUS" << 'PYEOF'
import json, sys, os

bus = sys.argv[1]
if not os.path.exists(bus):
    print("  Empty bus")
    sys.exit(0)

stats = {"pending": 0, "processed": 0, "by_type": {}, "by_priority": {}}
with open(bus) as f:
    for line in f:
        try:
            msg = json.loads(line.strip())
            stats[msg.get("status", "unknown")] = stats.get(msg.get("status", "unknown"), 0) + 1
            msg_type = msg.get("type", "unknown")
            stats["by_type"][msg_type] = stats["by_type"].get(msg_type, 0) + 1
            priority = msg.get("priority", "normal")
            stats["by_priority"][priority] = stats["by_priority"].get(priority, 0) + 1
        except json.JSONDecodeError:
            continue

print(f"  Pending: {stats.get('pending', 0)}")
print(f"  Processed: {stats.get('processed', 0)}")
print(f"  By type: {stats.get('by_type', {})}")
print(f"  By priority: {stats.get('by_priority', {})}")
PYEOF
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-status}" in
  mcp-discover)   mcp_discover ;;
  mcp-validate)   shift; mcp_validate "$@" ;;
  mcp-enable)     shift; mcp_enable "$@" ;;
  mcp-health)     shift; mcp_health_check "$@" ;;
  mcp-status)     mcp_status ;;
  msg-publish)    shift; msg_publish "$@" ;;
  msg-consume)    shift; msg_consume "$@" ;;
  msg-process)    shift; msg_process "$@" ;;
  msg-status)     msg_status ;;
  *)
    echo "Usage: mcp-manager.sh {mcp-*|msg-*}"
    ;;
esac
