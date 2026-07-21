#!/usr/bin/env bash
# self-improve/lib/llm-provider.sh
# LLM 能力提供者 + 健康监控 + 优雅降级 + 问题诊断
#
# 修复 v1.4:
# - C2: 分离 Python heredoc 与 bash 代码
# - S5: prompt 使用环境变量传参(防注入)
# - S2: 阻塞消息改 stderr
# - A3: flock macOS 兼容性

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FWK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MEMORY_DIR="${FWK_DIR}/.memory"
LLM_STATUS="${MEMORY_DIR}/.llm-status.json"
LLM_ALERTS="${MEMORY_DIR}/.llm-alerts.jsonl"

# ── LLM 健康探测 ─────────────────────────────────────────────────────────

_probe_anthropic() {
  local api_key="${ANTHROPIC_API_KEY:-}"
  [[ -z "$api_key" ]] && return 1
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
    -X POST "https://api.anthropic.com/v1/messages" \
    -H "x-api-key: ${api_key}" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d '{"model":"claude-3-5-haiku-20241022","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}' 2>/dev/null)
  case "$http_code" in
    200) echo "anthropic:ok" && return 0 ;;
    401) echo "anthropic:invalid_key" && return 1 ;;
    429) echo "anthropic:rate_limited" && return 1 ;;
    500|502|503) echo "anthropic:server_error:${http_code}" && return 1 ;;
    000) echo "anthropic:timeout" && return 1 ;;
    *) echo "anthropic:unknown:${http_code}" && return 1 ;;
  esac
}

_probe_openai() {
  local api_key="${OPENAI_API_KEY:-}"
  [[ -z "$api_key" ]] && return 1
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
    -X POST "https://api.openai.com/v1/chat/completions" \
    -H "Authorization: Bearer ${api_key}" \
    -H "Content-Type: application/json" \
    -d '{"model":"gpt-4o-mini","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}' 2>/dev/null)
  case "$http_code" in
    200) echo "openai:ok" && return 0 ;;
    401) echo "openai:invalid_key" && return 1 ;;
    429) echo "openai:rate_limited" && return 1 ;;
    500|502|503) echo "openai:server_error:${http_code}" && return 1 ;;
    000) echo "openai:timeout" && return 1 ;;
    *) echo "openai:unknown:${http_code}" && return 1 ;;
  esac
}

_probe_ollama() {
  command -v ollama &>/dev/null || return 1
  curl -s --max-time 3 http://localhost:11434/api/tags &>/dev/null || { echo "ollama:not_running"; return 1; }
  local models
  models=$(curl -s --max-time 5 http://localhost:11434/api/tags 2>/dev/null | \
    python3 -c "import json,sys;d=json.load(sys.stdin);print(','.join([m['name'] for m in d.get('models',[])]))" 2>/dev/null)
  [[ -z "$models" ]] && { echo "ollama:no_models"; return 1; }
  echo "ollama:ok"
  return 0
}

_probe_custom() {
  local endpoint="${LLM_ENDPOINT:-}"
  local api_key="${LLM_API_KEY:-}"
  local model="${LLM_MODEL:-}"
  [[ -z "$endpoint" || -z "$model" ]] && return 1
  endpoint="${endpoint%/}"
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
    -X POST "${endpoint}/chat/completions" \
    -H "Authorization: Bearer ${api_key}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${model}\",\"max_tokens\":10,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" 2>/dev/null)
  case "$http_code" in
    200) echo "custom:ok:${model}" && return 0 ;;
    401) echo "custom:invalid_key" && return 1 ;;
    404) echo "custom:model_not_found" && return 1 ;;
    429) echo "custom:rate_limited" && return 1 ;;
    500|502|503) echo "custom:server_error:${http_code}" && return 1 ;;
    000) echo "custom:timeout" && return 1 ;;
    *) echo "custom:unknown:${http_code}" && return 1 ;;
  esac
}

# ── 错误诊断 ─────────────────────────────────────────────────────────────

get_diagnosis() {
  local code="$1"
  case "$code" in
    no_provider)
      echo "❌ 没有配置 LLM Provider" >&2
      echo "修复: export LLM_ENDPOINT=..." >&2 ;;
    invalid_key)
      echo "❌ API Key 无效(401)" >&2
      echo "修复: 检查 key 是否过期" >&2 ;;
    model_not_found)
      echo "❌ 模型不存在(404)" >&2
      echo "修复: 检查模型名称" >&2 ;;
    rate_limited)
      echo "⚠️ 请求频率限制(429)" >&2
      echo "修复: 等待 60 秒后重试" >&2 ;;
    server_error)
      echo "⚠️ 服务器错误(5xx)" >&2
      echo "修复: 等待几分钟后重试" >&2 ;;
    timeout)
      echo "⚠️ 连接超时" >&2
      echo "修复: 检查网络连接" >&2 ;;
    not_running)
      echo "❌ Ollama 未运行" >&2
      echo "修复: ollama serve" >&2 ;;
    no_models)
      echo "❌ Ollama 没有模型" >&2
      echo "修复: ollama pull llama3.2" >&2 ;;
    *)
      echo "❌ 未知错误: ${code}" >&2 ;;
  esac
}

# ── 主检测函数 ───────────────────────────────────────────────────────────

detect_llm() {
  local provider="" model="" status="unavailable" error_code=""
  
  local result
  if result=$(_probe_custom); then
    provider="custom"; model=$(echo "$result" | cut -d: -f3); status="ok"
  elif result=$(_probe_anthropic); then
    provider="anthropic"; status="ok"
  elif result=$(_probe_openai); then
    provider="openai"; status="ok"
  elif result=$(_probe_ollama); then
    provider="ollama"; status="ok"
  else
    status="error"
    _probe_custom 2>/dev/null | grep -q "invalid_key" && error_code="custom:invalid_key"
    _probe_custom 2>/dev/null | grep -q "model_not_found" && error_code="custom:model_not_found"
    _probe_custom 2>/dev/null | grep -q "timeout" && error_code="custom:timeout"
    _probe_custom 2>/dev/null | grep -q "server_error" && error_code="custom:server_error"
    [[ -z "$error_code" ]] && error_code="no_provider"
  fi
  
  # 保存状态到 JSON
  _save_status "$provider" "$model" "$status" "$error_code"
  
  # 如果有错误,输出诊断
  if [[ "$status" != "ok" ]]; then
    echo ""
    get_diagnosis "$error_code"
  fi
}

_save_status() {
  local provider="$1" model="$2" status="$3" error_code="$4"
  python3 - "$provider" "$model" "$status" "$error_code" "$LLM_STATUS" << 'PYEOF'
import json, sys, time
provider, model, status, error_code, f = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
data = {
    "checked_at": time.strftime("%Y-%m-%dT%H:%M:%TZ", time.gmtime()),
    "provider": provider, "model": model, "status": status,
    "error_code": error_code,
    "features": {
        "rag": "semantic" if status == "ok" else "tfidf_fallback",
        "reasoning": "llm" if status == "ok" else "template_fallback",
        "exploration": "llm" if status == "ok" else "pattern_fallback",
        "routing": "heuristic", "reflection": "heuristic",
        "recovery": "deterministic", "evaluation": "deterministic",
        "prioritization": "deterministic"
    }
}
json.dump(data, open(f, "w"), indent=2)
emoji = "🟢" if status == "ok" else "🔴"
print(f"{emoji} LLM {status.upper()}: {provider}/{model}")
if error_code:
    print(f"   Error: {error_code}")
PYEOF
}

# ── 告警 ─────────────────────────────────────────────────────────────────

raise_alert() {
  local severity="$1" message="$2" action="${3:-}"
  python3 - "$severity" "$message" "$action" "$LLM_ALERTS" << 'PYEOF'
import json, sys, time
s, m, a, f = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
alert = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ"), "severity": s, "message": m, "action": a, "acknowledged": False}
json.dump(alert, open(f, "a"))
emoji = "🔴" if s == "critical" else "🟡" if s == "warning" else "🔵"
print(f"{emoji} [{s.upper()}] {m}")
PYEOF
}

show_alerts() {
  echo "═══ LLM 告警 ═══"
  [[ ! -f "$LLM_ALERTS" ]] && { echo "  无告警"; return; }
  python3 - "$LLM_ALERTS" << 'PYEOF'
import json, sys
alerts = [json.loads(l) for l in open(sys.argv[1]) if l.strip() and not json.loads(l).get("acknowledged")]
if not alerts:
    print("  ✅ 无未确认告警")
else:
    print(f"  {len(alerts)} 个未确认告警:")
    for a in alerts[-10:]:
        emoji = "🔴" if a["severity"] == "critical" else "🟡"
        print(f"  {emoji} [{a['severity']}] {a['message']}")
        if a.get("action"): print(f"     → {a['action']}")
PYEOF
}

# ── 智能调用(带降级) ─────────────────────────────────────────────────────

llm_call() {
  local prompt="$1" fallback="$2"
  
  [[ ! -f "$LLM_STATUS" ]] && detect_llm >/dev/null 2>&1
  local provider status
  provider=$(python3 -c "import json;print(json.load(open('$LLM_STATUS')).get('provider',''))" 2>/dev/null)
  status=$(python3 -c "import json;print(json.load(open('$LLM_STATUS')).get('status',''))" 2>/dev/null)
  
  if [[ "$status" != "ok" ]]; then
    echo "$fallback"; return 1
  fi
  
  local result=""
  case "$provider" in
    custom)
      result=$(_llm_call_custom "$prompt" 2>/dev/null) || result=""
      ;;
    anthropic)
      result=$(_llm_call_anthropic "$prompt" 2>/dev/null) || result=""
      ;;
    openai)
      result=$(_llm_call_openai "$prompt" 2>/dev/null) || result=""
      ;;
  esac
  
  if [[ -n "$result" ]]; then
    echo "$result"; return 0
  else
    raise_alert "warning" "LLM 调用失败: ${provider}" "检查 LLM 状态或切换 Provider"
    echo "$fallback"; return 1
  fi
}

_llm_call_custom() {
  local prompt="$1"
  LLM_PROMPT="$prompt" python3 << 'PYEOF'
import json, urllib.request, os
ep = os.environ.get("LLM_ENDPOINT", "")
key = os.environ.get("LLM_API_KEY", "")
model = os.environ.get("LLM_MODEL", "")
prompt = os.environ.get("LLM_PROMPT", "")
data = json.dumps({"model": model, "max_tokens": 1024, "messages": [{"role": "user", "content": prompt}], "stream": False}).encode()
req = urllib.request.Request(f"{ep}/chat/completions", data=data, headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
resp = urllib.request.urlopen(req, timeout=60)
content = resp.read().decode()
print(json.loads(content)["choices"][0]["message"]["content"])
PYEOF
}

_llm_call_anthropic() {
  local prompt="$1"
  LLM_PROMPT="$prompt" python3 << 'PYEOF'
import os
from anthropic import Anthropic
client = Anthropic(api_key=os.environ.get('ANTHROPIC_API_KEY'))
prompt = os.environ.get('LLM_PROMPT', '')
msg = client.messages.create(model='claude-3-5-haiku-20241022', max_tokens=1024, messages=[{'role': 'user', 'content': prompt}])
print(msg.content[0].text)
PYEOF
}

_llm_call_openai() {
  local prompt="$1"
  LLM_PROMPT="$prompt" python3 << 'PYEOF'
import os
from openai import OpenAI
client = OpenAI(api_key=os.environ.get('OPENAI_API_KEY'))
prompt = os.environ.get('LLM_PROMPT', '')
resp = client.chat.completions.create(model='gpt-4o-mini', max_tokens=1024, messages=[{'role': 'user', 'content': prompt}])
print(resp.choices[0].message.content)
PYEOF
}

# ── CLI ───────────────────────────────────────────────────────────────────

case "${1:-status}" in
  detect)     detect_llm ;;
  diagnose)   [[ -n "${2:-}" ]] && get_diagnosis "$2" || echo "Usage: llm-provider.sh diagnose <error_code>" ;;
  status)
    if [[ -f "$LLM_STATUS" ]]; then
      python3 - "$LLM_STATUS" << 'PYEOF'
import json, sys
s = json.load(open(sys.argv[1]))
print(f"Provider: {s.get('provider','none')} | Model: {s.get('model','none')} | Status: {s.get('status','?')}")
for feat, mode in s.get("features",{}).items():
    emoji = "🟢" if mode in ["llm","semantic","heuristic","deterministic"] else "🟡"
    print(f"  {emoji} {feat}: {mode}")
PYEOF
    else
      echo "No status — run 'detect' first"
    fi
    ;;
  raise-alert)  shift; raise_alert "$@" ;;
  alerts)       show_alerts ;;
  call)         shift; llm_call "$@" ;;
  *)            echo "Usage: llm-provider.sh {detect|diagnose|status|raise-alert|alerts|call}" ;;
esac
