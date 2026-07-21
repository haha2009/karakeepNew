#!/usr/bin/env bash
# monitor.sh - 框架监听/遥测
# 用法: bash monitor.sh <event_type> <json_data>
# 示例: bash monitor.sh hook_block '{"command":"rm -rf .claude/"}'

set -euo pipefail

MEMORY_DIR="${MEMORY_DIR:-.memory}"
TELEMETRY_FILE="$MEMORY_DIR/framework-telemetry.jsonl"
mkdir -p "$MEMORY_DIR"

EVENT_TYPE="${1:-unknown}"
EVENT_DATA="${2:-{}}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PWD_HASH=$(echo "$PWD" | md5sum | cut -c1-8)

# 写入 JSONL
echo "{\"ts\":\"$TIMESTAMP\",\"type\":\"$EVENT_TYPE\",\"project\":\"$PWD_HASH\",\"data\":$EVENT_DATA}" >> "$TELEMETRY_FILE"

# 保留最近 1000 条
tail -n 1000 "$TELEMETRY_FILE" > "$TELEMETRY_FILE.tmp" && mv "$TELEMETRY_FILE.tmp" "$TELEMETRY_FILE"

echo "📝 logged: $EVENT_TYPE"
