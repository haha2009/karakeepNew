#!/usr/bin/env bash
# protect-git.sh — PreToolUse Hook
# stdin: JSON { "tool_name": "Bash", "tool_input": { "command": "..." } }
# exit 0 = 放行, exit 2 = 拒绝

# Parse command from stdin JSON — read ALL stdin (fixes trailing-newline drop)
CMD=""
while IFS= read -r line || [ -n "$line" ]; do CMD="$CMD$line"; done
if command -v jq &>/dev/null; then
  PARSED=$(echo "$CMD" | jq -r '.tool_input.command' 2>/dev/null) || PARSED=""
else
  PARSED=$(echo "$CMD" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi
if [ -n "$PARSED" ]; then
  CMD="$PARSED"
fi
if [ -z "$CMD" ]; then
  echo "[Hook Git 防护] 警告:无法解析命令,已放行(非阻断)" >&2
  exit 0
fi
# Normalize: replace newlines/tabs with space
CMD=$(printf '%s' "$CMD" | tr '\n\r' '  ')

# 1. 禁止 force push (大小写不敏感, 精确词边界, 不误杀 --force-with-lease)
if printf '%s' "$CMD" | grep -qiE 'git[[:space:]]+push[[:space:]]+.*(--force([[:space:]]|$|[^-])|-f([[:space:]]|$|[^o]))'; then
  echo "[Hook Git 防护] 已拦截: 禁止 force push。" >&2
  echo "[Hook] 如需撤销,请走 git revert 或使用 --force-with-lease。" >&2
  exit 2
fi

# 2. 禁止 reset --hard (大小写不敏感, 精确词边界)
if printf '%s' "$CMD" | grep -qiE 'git[[:space:]]+reset[[:space:]]+.*--hard([[:space:]]|$|[^-[:alnum:]])'; then
  echo "[Hook Git 防护] 已拦截: 禁止 reset --hard(会丢失未提交改动)。" >&2
  echo "[Hook] 如需重置: git stash + git checkout <file> 等方式。" >&2
  exit 2
fi

# 3. 禁止强制删除分支 (branch -D, 大小写敏感区分 -d vs -D)
if printf '%s' "$CMD" | grep -qE 'git[[:space:]]+branch[[:space:]]+-D([[:space:]]|$|[^-[:alnum:]])'; then
  echo "[Hook Git 防护] 已拦截: 禁止强制删除分支 (branch -D)。" >&2
  echo "[Hook] 使用 branch -d (小写) 安全删除已合并分支。" >&2
  exit 2
fi

exit 0
