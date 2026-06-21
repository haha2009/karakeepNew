#!/usr/bin/env bash
# ============================================================
# clean-workspace.sh — Karakeep 工作区自动清理脚本
#
# 作用：每次 commit 前清理临时文件，确保工作区干净
#
# 用法：
#   bash scripts/clean-workspace.sh               # dry-run（默认安全模式）
#   bash scripts/clean-workspace.sh --dry-run     # 显式 dry-run
#   bash scripts/clean-workspace.sh --force       # 实际删除（需确认）
#   bash scripts/clean-workspace.sh --force --yes # 跳过确认，直接删除
#   bash scripts/clean-workspace.sh --check       # 检查模式：干净 exit 0，有文件 exit 1
#   bash scripts/clean-workspace.sh --help        # 帮助
#
# 安全保证：
#   - 绝不删除 Git 跟踪的文件
#   - 绝不删除白名单中的正规文件
#   - 默认 dry-run，需 --force 才实际删除
#   - 提供 --check 模式用于 CI/pre-commit 检测
# ============================================================
set -euo pipefail

# ============================================================
# 配置
# ============================================================
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# 输出颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 模式
DRY_RUN=true
SKIP_CONFIRM=false
CHECK_MODE=false
VERBOSE=false

# ============================================================
# 白名单：绝对不删除的文件（支持 glob）
# ============================================================
EXEMPT_FILES=(
  # 根目录正规脚本
  "start-dev.sh"
  "do-build.sh"
  "karakeep-linux.sh"
  # 核心配置文件
  "package.json"
  "pnpm-workspace.yaml"
  "turbo.json"
  ".gitignore"
  ".npmrc"
  ".nvmrc"
  ".env.sample"
  # 文档入口
  "README.md"
  "CONTRIBUTING.md"
  "SECURITY.md"
  "LICENSE"
  "AGENTS.md"
  "CLAUDE.md"
  "GEMINI.md"
)

# ============================================================
# 扫描类别定义 (name, find_command 配对)
# ============================================================
CATEGORY_NAMES=()
CATEGORY_COMMANDS=()

add_category() {
  CATEGORY_NAMES+=("$1")
  CATEGORY_COMMANDS+=("$2")
}

add_category "备份文件（根目录）" 'find . -maxdepth 1 -type f \( -name "*.bak" -o -name "*.bak2" -o -name "*.backup" -o -name "*.new" -o -name "*.working" -o -name "*.template" \) 2>/dev/null'
add_category "备份文件（嵌套 depth 2-3）" 'find . -maxdepth 3 -type f \( -name "*.bak" -o -name "*.bak2" -o -name "*.backup" -o -name "*.new" -o -name "*.working" -o -name "*.template" \) -not -path "./.git/*" -not -path "*/node_modules/*" -not -path "*/dist/*" -not -path "*/.next/*" -not -path "*/build/*" -not -path "*/data/*" -not -path "*/.pnpm-store/*" 2>/dev/null'
add_category "临时状态文档（根目录）" 'find . -maxdepth 1 -type f \( -name "ACCEPTANCE_*.md" -o -name "FINAL_*.md" -o -name "TASK_*.md" -o -name "IMPLEMENTATION_*.md" -o -name "COMPLETION_*.md" -o -name "WORKING_*.md" -o -name "*_STATUS.txt" -o -name "*_CHECKLIST.md" -o -name "VERIFICATION_*.md" -o -name "PRODUCTION_READY_*.md" \) 2>/dev/null'
add_category "临时任务追踪 JSON（根目录）" 'find . -maxdepth 1 -type f \( -name "*-todos*.json" -o -name "mark-*.json" -o -name "complete-*.json" -o -name "all-*-done.json" \) 2>/dev/null'
add_category "一次性脚本（根目录非白名单 .sh）" 'for f in *.sh 2>/dev/null; do [ -f "$f" ] || continue; skip=false; for exempt in "${EXEMPT_FILES[@]}"; do [ "$f" = "$exempt" ] && skip=true && break; done; $skip || echo "./$f"; done'
# 异常目录：匹配以单引号或空格开头的目录
# 使用独立变量避免引号嵌套问题
_abnormal_dir_cmd='find . -maxdepth 1 -type d \( -name "'"'"'*" -o -name " *" \) 2>/dev/null'
add_category "异常目录（特殊字符开头）" "$_abnormal_dir_cmd"

# ============================================================
# 辅助函数
# ============================================================
info()  { echo -e "${CYAN}[info]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ok]${NC}    $*"; }
err()   { echo -e "${RED}[err]${NC}   $*"; }

print_usage() {
  cat <<EOF
用法: bash scripts/clean-workspace.sh [选项]

选项:
  --dry-run     仅列出可清理的文件，不实际删除（默认）
  --force       实际删除文件（交互式确认）
  --force --yes 跳过确认直接删除
  --check       检查模式：有需要清理的文件则 exit 1
  --verbose     显示详细扫描信息
  --help        显示此帮助

示例:
  bash scripts/clean-workspace.sh                  # 预览
  bash scripts/clean-workspace.sh --force          # 确认后删除
  bash scripts/clean-workspace.sh --force --yes    # 直接删除
  bash scripts/clean-workspace.sh --check          # CI 检查
EOF
}

# 检查文件是否被 Git 跟踪
is_tracked() {
  git ls-files --error-unmatch "$1" &>/dev/null
}

# 检查文件是否在白名单中
is_exempt() {
  local file="$1"
  local basename
  basename="$(basename "$file")"
  for exempt in "${EXEMPT_FILES[@]}"; do
    # 支持 glob 匹配
    case "$basename" in
      $exempt) return 0 ;;
    esac
  done
  return 1
}

# 检查文件是否是已存在的正规产物（在 .codestable/、scripts/、docs/ 等目录中）
is_legitimate_artifact() {
  local file="$1"
  # 正规目录中的文件不清理
  case "$file" in
    ./.codestable/*|./scripts/*|./docs/*|./docker/*|./charts/*|./kubernetes/*|./patches/*|./.github/*) return 0 ;;
  esac
  return 1
}

# ============================================================
# 主清理逻辑
# ============================================================
TOTAL_FILES=0
TOTAL_DELETED=0
declare -a FILES_TO_DELETE=()

scan_category() {
  local category_name="$1"
  local find_cmd="$2"
  local files
  files="$(eval "$find_cmd" 2>/dev/null)" || true

  if [ -z "$files" ]; then
    return
  fi

  local count=0
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    [ ! -e "$file" ] && continue

    # 安全检查：跳过 Git 跟踪的文件
    if is_tracked "$file"; then
      continue
    fi

    # 安全检查：跳过白名单文件
    if is_exempt "$file"; then
      continue
    fi

    # 安全检查：跳过正规产物（在受管目录中的）
    if is_legitimate_artifact "$file"; then
      continue
    fi

    FILES_TO_DELETE+=("$file")
    count=$((count + 1))
  done <<< "$files"

  if [ "$count" -gt 0 ]; then
    total_found=$((TOTAL_FILES + count))
    TOTAL_FILES=$total_found
  fi
}

execute_cleanup() {
  local mode="$1"  # "dry-run" or "force"

  # 先扫描所有类别
  for i in "${!CATEGORY_NAMES[@]}"; do
    scan_category "${CATEGORY_NAMES[$i]}" "${CATEGORY_COMMANDS[$i]}"
  done

  if [ "$TOTAL_FILES" -eq 0 ]; then
    ok "工作区干净，无临时文件需要清理。"
    return 0
  fi

  echo ""
  warn "发现 $TOTAL_FILES 个可清理的文件："
  echo ""

  # 按类别分组显示
  for i in "${!CATEGORY_NAMES[@]}"; do
    local category="${CATEGORY_NAMES[$i]}"
    local find_cmd="${CATEGORY_COMMANDS[$i]}"
    local files
    files="$(eval "$find_cmd" 2>/dev/null)" || true
    [ -z "$files" ] && continue

    local showed_header=false
    while IFS= read -r file; do
      [ -z "$file" ] && continue
      [ ! -e "$file" ] && continue
      is_tracked "$file" && continue
      is_exempt "$file" && continue
      is_legitimate_artifact "$file" && continue

      if ! $showed_header; then
        echo -e "  ${YELLOW}[$category]${NC}"
        showed_header=true
      fi
      echo "    • $file"
    done <<< "$files"
  done

  echo ""

  if [ "$mode" = "dry-run" ]; then
    info "这是 dry-run 模式。使用 --force 执行实际清理。"
    return 0
  fi

  # force 模式：询问确认
  if ! $SKIP_CONFIRM; then
    echo -n "确认删除以上 $TOTAL_FILES 个文件？(y/N) "
    read -r response
    case "$response" in
      [yY][eE][sS]|[yY]) ;;
      *)
        info "已取消。"
        return 1
        ;;
    esac
  fi

  # 实际删除
  for file in "${FILES_TO_DELETE[@]}"; do
    if [ -f "$file" ]; then
      rm -f "$file"
      TOTAL_DELETED=$((TOTAL_DELETED + 1))
    elif [ -d "$file" ]; then
      rmdir "$file" 2>/dev/null || rm -rf "$file"
      TOTAL_DELETED=$((TOTAL_DELETED + 1))
    fi
  done

  echo ""
  ok "已删除 $TOTAL_DELETED 个临时文件。"
  return 0
}

# ============================================================
# 参数解析
# ============================================================
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
    --force)
      DRY_RUN=false
      ;;
    --yes)
      SKIP_CONFIRM=true
      ;;
    --check)
      CHECK_MODE=true
      ;;
    --verbose)
      VERBOSE=true
      ;;
    --help|-h)
      print_usage
      exit 0
      ;;
    *)
      err "未知参数: $arg"
      print_usage
      exit 1
      ;;
  esac
done

# ============================================================
# 执行
# ============================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Karakeep 工作区清理工具${NC}"
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo ""

if $CHECK_MODE; then
  # 检查模式：只扫描不删除，干净 exit 0，否则 exit 1
  for i in "${!CATEGORY_NAMES[@]}"; do
    scan_category "${CATEGORY_NAMES[$i]}" "${CATEGORY_COMMANDS[$i]}"
  done

  if [ "$TOTAL_FILES" -eq 0 ]; then
    ok "工作区干净。"
    exit 0
  else
    err "发现 $TOTAL_FILES 个临时文件！请运行 bash scripts/clean-workspace.sh --dry-run 查看。"
    exit 1
  fi
fi

if $DRY_RUN; then
  info "安全模式（dry-run）— 仅列出，不删除"
  echo ""
  execute_cleanup "dry-run"
else
  execute_cleanup "force"
fi

echo ""
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
exit 0
