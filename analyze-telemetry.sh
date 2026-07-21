#!/usr/bin/env bash
# analyze-telemetry.sh - 分析框架遥测数据
# 产出: .memory/framework-health.md (可读报告)

set -euo pipefail

MEMORY_DIR="${MEMORY_DIR:-.memory}"
TELEMETRY_FILE="$MEMORY_DIR/framework-telemetry.jsonl"
REPORT_FILE="$MEMORY_DIR/framework-health.md"

if [[ ! -f "$TELEMETRY_FILE" ]]; then
  echo "📊 暂无遥测数据"
  exit 0
fi

TOTAL=$(wc -l < "$TELEMETRY_FILE" | tr -d ' ')
HOOK_BLOCKS=$(grep -c '"type":"hook_block"' "$TELEMETRY_FILE" 2>/dev/null) || HOOK_BLOCKS=0
HOOK_ALLOWS=$(grep -c '"type":"hook_allow"' "$TELEMETRY_FILE" 2>/dev/null) || HOOK_ALLOWS=0
INJECTS=$(grep -c '"type":"inject"' "$TELEMETRY_FILE" 2>/dev/null) || INJECTS=0
SKILL_INVOCES=$(grep -c '"type":"skill_invoke"' "$TELEMETRY_FILE" 2>/dev/null) || SKILL_INVOCES=0
ERRORS=$(grep -c '"type":"error"' "$TELEMETRY_FILE" 2>/dev/null) || ERRORS=0
FALSE_POSITIVES=$(grep -c '"type":"false_positive"' "$TELEMETRY_FILE" 2>/dev/null) || FALSE_POSITIVES=0

# 生成报告
cat > "$REPORT_FILE" << REPORT
# 框架健康报告

> 生成时间: $(date -u +"%Y-%m-%d %H:%M:%SZ")
> 数据源: $TELEMETRY_FILE ($TOTAL 条事件)

## 概览

| 指标 | 数值 |
|---|---|
| 总事件 | $TOTAL |
| Hook 拦截 | $HOOK_BLOCKS |
| Hook 放行 | $HOOK_ALLOWS |
| 注入次数 | $INJECTS |
| 技能调用 | $SKILL_INVOCES |
| 误报(已报告) | $FALSE_POSITIVES |
| 错误 | $ERRORS |

## 诊断

$([[ $FALSE_POSITIVES -gt 0 ]] && echo "⚠️ 有 $FALSE_POSITIVES 个误报 → 检查 rules 是否需要放松" || echo "✅ 无误报")
$([[ $ERRORS -gt 0 ]] && echo "⚠️ 有 $ERRORS 个错误 → 查看遥测详情" || echo "✅ 无错误")
$([[ $HOOK_BLOCKS -gt 0 ]] && echo "🔒 Hook 已拦截 $HOOK_BLOCKS 次危险操作" || echo "ℹ️ Hook 尚未拦截")

## 建议

$(if [[ $FALSE_POSITIVES -gt 3 ]]; then echo "- 考虑将高频误加入白名单"; else echo "- 当前精度可接受"; fi)
$(if [[ $ERRORS -gt 0 ]]; then echo "- 优先修复遥测中的错误"; else echo "- 继续观察"; fi)
REPORT

echo "📊 报告已写入: $REPORT_FILE"
echo ""
echo "概览: $TOTAL 事件 | $HOOK_BLOCKS 拦截 | $FALSE_POSITIVES 误报 | $ERRORS 错误"
