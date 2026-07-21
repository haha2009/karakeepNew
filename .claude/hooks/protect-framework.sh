#!/usr/bin/env bash

# Block helper: log + exit 2
block() {
  local log_file
  log_file="$(dirname "$SCRIPT_DIR")/.memory/hook-blocks.log"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) BLOCK: ${CMD}" >> "$log_file" 2>/dev/null || true
  echo "  💡 如果这是误杀,运行: bash .claude/commands/report-false-positive.sh \"${CMD}\"" >&2
  exit 2
}

# Timing: record start
_HOOK_START=$(date +%s%N 2>/dev/null || python3 -c 'import time;print(int(time.time()*1e9))' 2>/dev/null || echo 0)

# Log slow hook on exit
_log_timing() {
  [[ "$_HOOK_START" == "0" ]] && return
  local end_ns
  end_ns=$(date +%s%N 2>/dev/null || python3 -c 'import time;print(int(time.time()*1e9))' 2>/dev/null || echo 0)
  local ms=$(( (end_ns - _HOOK_START) / 1000000 ))
  if [[ "$ms" -gt 500 ]]; then
    local timing_file
    timing_file="$(dirname "$SCRIPT_DIR")/.memory/hook-timing.log"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) SLOW: ${ms}ms | cmd=${CMD:0:80}" >> "$timing_file" 2>/dev/null || true
  fi
}

# Parse command from stdin JSON
CMD=""
while IFS= read -r line || [ -n "$line" ]; do CMD="$CMD$line"; done

if command -v jq &>/dev/null; then
  PARSED=$(echo "$CMD" | jq -r '.tool_input.command' 2>/dev/null) || PARSED=""
else
  PARSED=$(echo "$CMD" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi
if [ -n "$PARSED" ]; then CMD="$PARSED"; fi
if [ -z "$CMD" ]; then exit 0; fi

CMD=$(printf '%s' "$CMD" | tr '\n\r' '  ')
trap _log_timing EXIT

# Check whitelist first(user-configurable bypass)
BYPASS_FILE="$(dirname "$SCRIPT_DIR")/.claude/hook-bypass.json"
if [[ -f "$BYPASS_FILE" ]] && command -v python3 >/dev/null 2>&1; then
  if python3 - "$CMD" "$BYPASS_FILE" 2>/dev/null << 'PYEOF'
import json, sys, re
cmd, bypass_file = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(bypass_file))
    if not data.get("enabled", True):
        sys.exit(1)
    for pattern in data.get("whitelisted_patterns", []):
        if re.search(pattern, cmd):
            sys.exit(0)
except Exception:
    pass
sys.exit(1)
PYEOF
  then
    exit 0
  fi
fi

# 1. 禁止技能安装器 + 解释器绕过
if printf '%s' "$CMD" | grep -qiE '(npx|yarn|pnpm|bunx)[[:space:]]+skills[[:space:]]+add|npx[[:space:]]+@anthropic-ai|python[23]?[[:space:]]+-c|node[[:space:]]+-e|ruby[[:space:]]+-e|perl[[:space:]]+-e|eval[[:space:]]|bash[[:space:]]+-c|sh[[:space:]]+-c'; then
  echo ""
  echo "🚫 已拦截: 外部安装器/解释器禁止直接写入项目技能目录"
  echo "   命令: ${CMD}"
  echo "   原因: 防止通过解释器(nodepython/eval/bash -c)绕过 Hook 删除文件"
  echo "   改用: 全局安装 -> npx skills add -g <repo>"
  echo ""
  block
fi

# 2. 禁止删除/移动框架配置目录(精确词边界)
if printf '%s' "$CMD" | grep -qiE '(^|[;&|])[[:space:]]*(rm|mv)[[:space:]]+.*(\.claude(/|$)|\.agents(/|$))'; then
  echo "🚫 已拦截: 禁止删除或移动框架配置目录"
  echo "   命令: ${CMD}"
  echo "   原因: .claude/ 和 .agents/ 包含 Agent 配置和技能"
  echo "   改用: 编辑文件后 git commit,无需删除目录"
  echo ""
  block
fi
if printf '%s' "$CMD" | grep -qiE 'git[[:space:]]+rm[[:space:]]+.*(\.claude|\.agents)'; then
  echo ""
  echo "🚫 已拦截: git rm 禁止删除框架配置目录"
  echo "   命令: ${CMD}"
  echo "   原因: 即使是 git rm 也不允许删除配置目录"
  echo "   改用: git rm 单个文件(非目录),或编辑后 commit"
  echo ""
  block
fi

# 3. 保护状态文件(精确匹配,不拦 loop.md/CLAUDE.md.bak)
if printf '%s' "$CMD" | grep -qE '(^|[[:space:]]|\/)(LOOP|STATE)\.md([[:space:]]|$)'; then
  echo ""
  echo "🚫 已拦截: 禁止删除或覆盖循环状态文件"
  echo "   命令: ${CMD}"
  echo "   原因: LOOP.md/STATE.md 记录自动化循环状态"
  echo "   改用: 编辑文件内容,而非删除"
  echo ""
  block
fi
if printf '%s' "$CMD" | grep -qE '(^|[[:space:]]|\/)gate\.yaml([[:space:]]|$)'; then
  echo ""
  echo "🚫 已拦截: 禁止删除或覆盖 gate.yaml"
  echo "   命令: ${CMD}"
  echo "   原因: gate.yaml 控制循环门禁配置"
  echo "   改用: 编辑文件内容,而非删除"
  echo ""
  block
fi

# 4. 禁止覆盖 .env(精确匹配,不拦 .env.local,cat 允许)
if printf '%s' "$CMD" | grep -qE '(rm|mv|>)' && printf '%s' "$CMD" | grep -qE '(^|[[:space:]]|\/)\.env($)'; then
  echo ""
  echo "🚫 已拦截: 禁止删除或覆盖 .env 文件"
  echo "   命令: ${CMD}"
  echo "   原因: .env 包含敏感配置(密钥、连接串)"
  echo "   改用: 手动确认后执行,或编辑 .env.example"
  echo ""
  block
fi

# 5. 保护核心入口文档(精确匹配,不拦 .md.bak)
if printf '%s' "$CMD" | grep -qE '(rm|mv|>)' && printf '%s' "$CMD" | grep -qE '(^|[[:space:]]|\/)(CLAUDE|AGENTS|README)\.md($)'; then
  echo ""
  echo "🚫 已拦截: 禁止删除或覆盖核心入口文档"
  echo "   命令: ${CMD}"
  echo "   原因: CLAUDE.md/AGENTS.md/README.md 是项目入口文档"
  echo "   改用: 编辑文件内容,而非删除"
  echo ""
  block
fi

# 6. 禁止覆盖 .claude/ 内部文件(仅拦截写入)
if printf '%s' "$CMD" | grep -qE '>[[:space:]]+.*\.claude/'; then
  echo ""
  echo "🚫 已拦截: 禁止覆盖 .claude/ 内部文件"
  echo "   命令: ${CMD}"
  echo "   原因: .claude/ 包含 Agent 配置和 hooks"
  echo "   改用: 使用 Edit 工具编辑,而非 bash 重定向"
  echo ""
  block
fi

exit 0
