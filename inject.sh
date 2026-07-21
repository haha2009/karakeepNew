#!/usr/bin/env bash
# inject.sh — 将 MCF 框架注入到目标项目
# 用法: bash inject.sh [/path/to/target-project] [--dry-run]
# 效果: 复制 template/ + AGENTS.md 到目标项目，填充占位符
set -euo pipefail

FRAMEWORK_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${2:-}"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  echo "MCF 框架注入器"
  echo "用法: bash inject.sh /path/to/target-project [--dry-run]"
  echo ""
  echo "  --dry-run  仅预览改动，不写磁盘"
  echo "  --help     显示此帮助"
  exit 0
fi

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "用法: bash inject.sh /path/to/target-project [--dry-run]"
  echo "示例: bash inject.sh ../my-app"
  exit 1
fi
if [ ! -d "$TARGET" ]; then
  echo "目标目录不存在: $TARGET"
  exit 1
fi
if [ ! -w "$TARGET" ]; then
  echo "目标目录不可写: $TARGET"
  exit 1
fi

DRY_RUN=false
[ "$MODE" = "--dry-run" ] && DRY_RUN=true

# Cross-platform sed in-place
SED_INPLACE=(-i '')
if [[ "$(uname -s)" != Darwin ]]; then
  SED_INPLACE=(-i)
fi

# 冲突检测——对比 template/ 内容与目标项目已有文件
CONFLICTS=""
while IFS= read -r f; do
  rel="${f#$FRAMEWORK_DIR/template/}"
  [ -f "$TARGET/$rel" ] && CONFLICTS="$CONFLICTS  $TARGET/$rel"$'\n'
done < <(find "$FRAMEWORK_DIR/template" -type f)
# 额外检查 AGENTS.md
[ -f "$TARGET/AGENTS.md" ] && CONFLICTS="$CONFLICTS  $TARGET/AGENTS.md"$'\n'
if [ -n "$CONFLICTS" ]; then
  echo "⚠️ 以下文件已存在，将被覆盖："
  echo "$CONFLICTS"
  if [ "$DRY_RUN" = false ]; then
    echo "继续请按 Enter，取消请 Ctrl+C"
    read -r
  fi
fi

if [ "$DRY_RUN" = true ]; then
  echo "📦 [DRY RUN] 将注入框架到 $TARGET ..."
  echo "  文件清单：template/ (全部) + AGENTS.md"
  [ -n "$CONFLICTS" ] && echo "  冲突文件：$(echo "$CONFLICTS" | wc -l) 个将被覆盖"
  echo "✅ DRY RUN 完成，未写入任何文件"
  exit 0
fi

# ── Pre-flight: 版本检测 + 技能冲突 ─────────────────────────────
echo "📦 注入框架到 $TARGET ..."

FRAMEWORK_VERSION=$(cat "$FRAMEWORK_DIR/.framework-version" 2>/dev/null || echo "v1.0.0")
USER_VERSION=""
IS_UPGRADE=false

if [[ -f "$TARGET/.framework-version" ]]; then
  USER_VERSION=$(cat "$TARGET/.framework-version")
  if [[ "$USER_VERSION" != "$FRAMEWORK_VERSION" ]]; then
    IS_UPGRADE=true
    echo "🔄 升级: $USER_VERSION → $FRAMEWORK_VERSION"
    
    # Version comparison for major upgrades
    OLD_MAJOR=$(echo "$USER_VERSION" | sed 's/v\([0-9]*\).*/\1/')
    NEW_MAJOR=$(echo "$FRAMEWORK_VERSION" | sed 's/v\([0-9]*\).*/\1/')
    if [[ "$OLD_MAJOR" -lt "$NEW_MAJOR" ]]; then
      echo "⚠️ 大版本升级 detected - 建议查看 CHANGELOG"
    fi
  fi
fi

# Skills conflict detection: preserve user custom skills
SKILLS_BACKUP=""
if [[ "$IS_UPGRADE" && -d "$TARGET/.claude/skills" ]]; then
  # Find user custom skills (not in our template)
  SKILLS_BACKUP=$(mktemp -d)
  for skill_dir in "$TARGET/.claude/skills"/*/; do
    skill_name=$(basename "$skill_dir")
    if [[ ! -d "$FRAMEWORK_DIR/template/.claude/skills/$skill_name" ]]; then
      # User custom skill - preserve it
      cp -R "$skill_dir" "$SKILLS_BACKUP/"
      echo "  💾 保留用户技能: $skill_name"
    fi
  done
fi

echo "📦 注入框架到 $TARGET ..."

# 复制 template/ 目录
cp -R "$FRAMEWORK_DIR/template/." "$TARGET/"

# Restore user custom skills after cp -R
if [[ -n "$SKILLS_BACKUP" && -d "$SKILLS_BACKUP" ]]; then
  # Find actual skill dirs (handles empty backup)
  found_skills=false
  for skill_dir in "$SKILLS_BACKUP"/*/; do
    [[ -d "$skill_dir" ]] || continue
    found_skills=true
    skill_name=$(basename "$skill_dir")
    cp -R "$skill_dir" "$TARGET/.claude/skills/$skill_name/"
    echo "  ♻️ 恢复用户技能: $skill_name"
  done
  rm -rf "$SKILLS_BACKUP"
  [[ "$found_skills" == false ]] && echo "  ℹ️ 无用户自定义技能需恢复"
fi

# ── Migration logging ────────────────────────────────────────────
mkdir -p "$TARGET/.memory"
MIGRATION_LOG="$TARGET/.memory/migration-log.md"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [[ "$IS_UPGRADE" == true ]]; then
  {
    echo "## $TIMESTAMP - Upgrade $USER_VERSION → $FRAMEWORK_VERSION"
    echo "- Framework templates: force-updated"
    echo "- User skills: preserved"
  } >> "$MIGRATION_LOG"
  echo "  📝 Migration logged"
fi
cp "$FRAMEWORK_DIR/AGENTS.md" "$TARGET/AGENTS.md"
mkdir -p "$TARGET/.agents/skills"
cp "$FRAMEWORK_DIR/.framework-version" "$TARGET/.framework-version"
mkdir -p "$TARGET/.claude/skills"

# 询问项目信息，填充占位符
read -p "项目名 (用于 CLAUDE.md) [MyApp]: " PROJECT_NAME
PROJECT_NAME="${PROJECT_NAME:-MyApp}"
read -p "技术栈 (e.g. Next.js+TS, Kotlin+Compose) [Web]: " TECH_STACK
TECH_STACK="${TECH_STACK:-Web}"
read -p "构建命令 (e.g. npm run build, ./gradlew assembleDebug) [npm run build]: " BUILD_CMD
BUILD_CMD="${BUILD_CMD:-npm run build}"
read -p "测试命令 (e.g. npm test, ./gradlew test) [npm test]: " TEST_CMD
TEST_CMD="${TEST_CMD:-npm test}"
read -p "代码风格检查 (e.g. npm run lint, npx prettier --check .) [npm run lint]: " LINT_CMD
LINT_CMD="${LINT_CMD:-npm run lint}"

# 转义 sed 替换中的特殊字符
esc() { printf '%s\n' "$1" | sed 's/[\/&|'"'"'\\]/\\&/g'; }
PROJECT_NAME_E=$(esc "$PROJECT_NAME")
TECH_STACK_E=$(esc "$TECH_STACK")
BUILD_CMD_E=$(esc "$BUILD_CMD")
TEST_CMD_E=$(esc "$TEST_CMD")
LINT_CMD_E=$(esc "$LINT_CMD")

# 填充占位符（只对包含占位符的文件执行）
sed "${SED_INPLACE[@]}" "s/{{PROJECT_NAME}}/$PROJECT_NAME_E/g" "$TARGET/CLAUDE.md"
sed "${SED_INPLACE[@]}" "s/{{TECH_STACK}}/$TECH_STACK_E/g" "$TARGET/CLAUDE.md"
sed "${SED_INPLACE[@]}" "s|{{BUILD_CMD}}|$BUILD_CMD_E|g" "$TARGET/CLAUDE.md"
sed "${SED_INPLACE[@]}" "s|{{BUILD_CMD}}|$BUILD_CMD_E|g" "$TARGET/AGENTS.md"
sed "${SED_INPLACE[@]}" "s|{{TEST_CMD}}|$TEST_CMD_E|g" "$TARGET/AGENTS.md"
sed "${SED_INPLACE[@]}" "s|{{LINT_CMD}}|$LINT_CMD_E|g" "$TARGET/AGENTS.md"

# .gitignore 追加（防重复）
if ! grep -qF ".claude/settings.local.json" "$TARGET/.gitignore" 2>/dev/null; then
  echo "" >> "$TARGET/.gitignore"
  echo "# MCF 框架配置（仅本地覆盖）" >> "$TARGET/.gitignore"
  echo ".claude/settings.local.json" >> "$TARGET/.gitignore"
fi


# ── 自动安装 mattpocock 工程技能 ──
echo ""
echo "📦 安装 mattpocock 工程技能..."
if command -v npx &>/dev/null; then
  if npx @mattpocock/skills@latest add -g 2>&1; then
    echo "  ✅ 技能已安装"
    echo "  📌 首次使用请在 Claude Code 中运行: /setup-matt-pocock-skills"
  else
    echo "  ⚠️ 安装失败,请稍后手动执行: npx @mattpocock/skills add -g"
  fi
else
  echo "  ⚠️ 未找到 npx,请安装 Node.js 后执行: npx @mattpocock/skills add -g"
fi
# ── 检查残余占位符（全目录扫描） ──
REMAINING=$(grep -r '{{' "$TARGET" --include='*.md' --include='*.json' 2>/dev/null || true)
if [ -n "$REMAINING" ]; then
  echo ""
  echo "⚠️ 以下文件仍有未替换占位符，请手动编辑："
  echo "$REMAINING" | awk -F: '!seen[$1]++{print "   " $1}'
fi


echo ""
echo "✅ 注入完成！"
echo ""
echo "下一步："
echo "  1. 编辑 $TARGET/CLAUDE.md 补充项目专属信息"
if [[ "${INSTALL_SKILLS:-}" != "n" && "${INSTALL_SKILLS:-}" != "N" ]]; then
  echo "  2. 在 Claude Code 中运行 /setup-matt-pocock-skills 完成技能配置"
fi
echo "  4. 测试 Hook:"
echo "     cd $TARGET"
echo "     echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npx skills add test/test\"}}' | .claude/hooks/protect-framework.sh"
echo "     echo \$?  # 应输出 2（拦截成功）"
echo "  5. 编辑 $TARGET/.claude/skills/ 添加项目特有技能"
echo "  6. 若上面有 ⚠️ 提示，打开对应文件手动填写"
echo ""
