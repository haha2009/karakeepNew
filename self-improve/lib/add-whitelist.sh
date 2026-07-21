#!/usr/bin/env bash
# self-improve/lib/add-whitelist.sh
# Add a pattern to hook-bypass.json whitelist

set -eo pipefail

FWK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BYPASS_FILE="${FWK_DIR}/template/.claude/hook-bypass.json"

[[ -z "$1" ]] && { echo "Usage: add-whitelist.sh <regex-pattern>"; exit 1; }

PATTERN="$1"

# Add pattern using python3
python3 - "$BYPASS_FILE" "$PATTERN" << 'PYEOF'
import json, sys

bypass_file, pattern = sys.argv[1], sys.argv[2]

try:
    with open(bypass_file) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {"version": "1.0", "whitelisted_patterns": [], "enabled": True}

if pattern not in data["whitelisted_patterns"]:
    data["whitelisted_patterns"].append(pattern)
    with open(bypass_file, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(f"✅ Added to whitelist: {pattern}")
else:
    print(f"⚠️ Already whitelisted: {pattern}")
PYEOF
