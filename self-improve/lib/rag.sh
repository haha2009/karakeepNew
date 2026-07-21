#!/usr/bin/env bash
# self-improve/lib/rag.sh
# RAG + Reasoning — TF-IDF 回退 + LLM 语义增强

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FWK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MEMORY_DIR="${FWK_DIR}/.memory"
KNOWLEDGE_DIR="${MEMORY_DIR}/knowledge"
REASONING_LOG="${MEMORY_DIR}/.reasoning-chain.jsonl"
PYTHON_MODULE="${SCRIPT_DIR}/rag_reasoning.py"
LLM_PROVIDER="${SCRIPT_DIR}/llm-provider.sh"

mkdir -p "$KNOWLEDGE_DIR"

# ── 索引(TF-IDF,始终可用) ────────────────────────────────────────────────

rag_index() {
  echo "═══ RAG Indexing(TF-IDF) ═══"
  python3 "$PYTHON_MODULE" index
}

# ── TF-IDF 检索(回退模式) ─────────────────────────────────────────────────

rag_retrieve_tfidf() {
  local query="$1"
  python3 "$PYTHON_MODULE" retrieve "$query"
}

# ── LLM 语义检索(增强模式) ────────────────────────────────────────────────

rag_retrieve() {
  local query="$1"
  local max_results="${2:-5}"
  
  local llm_status
  llm_status=$(bash "$LLM_PROVIDER" status 2>/dev/null | sed -n 's/.*Status: \([a-z]*\).*/\1/p')
  # Fallback: check via detect
  if [[ "$llm_status" != "ok" ]]; then
    llm_status=$(bash "$LLM_PROVIDER" detect 2>/dev/null | sed -n 's/LLM \([A-Z]*\).*/\1/p' | tr '[:upper:]' '[:lower:]')
    [[ "$llm_status" == "ok" ]] || llm_status=""
  fi
  
  if [[ "$llm_status" != "ok" ]]; then
    echo "═══ RAG Retrieve(TF-IDF fallback) ═══"
    rag_retrieve_tfidf "$query" "$max_results"
    return
  fi
  echo "═══ RAG Retrieve(LLM Semantic) ═══"
  
  local candidates
  candidates=$(python3 "$PYTHON_MODULE" retrieve-raw "$query" 2>/dev/null | head -20)
  if [[ -z "$candidates" ]]; then
    echo "  No candidates found"
    return 1
  fi
  
  local llm_prompt="## 查询
${query}

## 候选文档
${candidates}

## 任务
1. 从候选文档中找出与查询最相关的 3-5 条
2. 用一句话总结每条的相关性原因
3. 如果候选都不相关,回答「无相关经验」"
  
  local llm_result
  llm_result=$(bash "$LLM_PROVIDER" call "$llm_prompt" "" 2>/dev/null)
  
  if [[ -n "$llm_result" ]]; then
    echo "  LLM 语义分析:"
    echo "$llm_result" | sed 's/^/    /'
  else
    echo "  LLM 不可用,回退到 TF-IDF"
    rag_retrieve_tfidf "$query" "$max_results"
  fi
}

# ── CoT 推理(LLM 驱动) ────────────────────────────────────────────────────

cot_reasoning() {
  local problem="$1"
  
  local llm_status
  llm_status=$(bash "$LLM_PROVIDER" status 2>/dev/null | sed -n 's/.*Status: \([a-z]*\).*/\1/p')
  if [[ "$llm_status" != "ok" ]]; then
    llm_status=$(bash "$LLM_PROVIDER" detect 2>/dev/null | sed -n 's/LLM \([A-Z]*\).*/\1/p' | tr '[:upper:]' '[:lower:]')
    [[ "$llm_status" == "ok" ]] || llm_status=""
  fi
  if [[ "$llm_status" != "ok" ]]; then
    echo "═══ CoT Reasoning(Template fallback) ═══"
    python3 "$PYTHON_MODULE" cot "$problem"
    return
  fi
  
  echo "═══ CoT Reasoning(LLM-powered) ═══"
  
  local llm_prompt="## 问题
${problem}

## 请用 Chain-of-Thought 推理分析这个问题
1. 理解问题:核心是什么?约束是什么?
2. 分析原因:可能的原因有哪些?
3. 评估方案:每个方案的可行性、风险、影响
4. 选择方案:推荐最佳方案并说明理由
5. 验证计划:如何验证方案有效?

请给出具体的推理过程,不要只给标题。"
  
  local llm_result
  llm_result=$(bash "$LLM_PROVIDER" call "$llm_prompt" "" 2>/dev/null)
  if [[ -n "$llm_result" ]]; then
    echo "$llm_result"
  else
    echo "  LLM 不可用,回退到模板"
    python3 "$PYTHON_MODULE" cot "$problem"
  fi
}

# ── ReAct 推理(LLM 驱动) ───────────────────────────────────────────────────

react_reasoning() {
  local goal="$1"
  
  local llm_status
  llm_status=$(bash "$LLM_PROVIDER" status 2>/dev/null | grep "Status" | awk '{print $2}')
  
  if [[ "$llm_status" != "ok" ]]; then
    echo "═══ ReAct Reasoning(Template fallback) ═══"
    python3 "$PYTHON_MODULE" react "$goal"
    return
  fi
  
  echo "═══ ReAct Reasoning(LLM-powered) ═══"
  
  local llm_prompt="## 目标
${goal}

## 请用 ReAct(Reasoning + Acting)方法思考
1. Thought: 分析当前状况,确定下一步行动
2. Action: 执行具体操作(搜索/测试/修复)
3. Observation: 观察结果,调整策略
4. 重复直到目标达成

请给出具体的思考和操作过程。"
  
  local llm_result
  llm_result=$(bash "$LLM_PROVIDER" call "$llm_prompt" "" 2>/dev/null)
  
  if [[ -n "$llm_result" ]]; then
    echo "$llm_result"
  else
    echo "  LLM 不可用,回退到模板"
    python3 "$PYTHON_MODULE" react "$goal"
  fi
}

# ── 状态 ──────────────────────────────────────────────────────────────────

rag_status() {
  echo "═══ RAG + Reasoning Status ═══"
  python3 "$PYTHON_MODULE" status 2>/dev/null
}

# ── CLI ──────────────────────────────────────────────────────────────────────

case "${1:-}" in
  index)      rag_index ;;
  retrieve)   shift; rag_retrieve "$@" ;;
  cot)        shift; cot_reasoning "$@" ;;
  react)      shift; react_reasoning "$@" ;;
  status)     rag_status ;;
  *)
    echo "Usage: rag.sh {index|retrieve <query>|cot <problem>|react <goal>|status}"
    ;;
esac
