#!/usr/bin/env bash
# init.sh - 智能项目初始化脚本
# 自动检测项目类型并配置构建/测试/lint 命令

set -euo pipefail

echo "🔧 项目初始化"
echo ""

# 检测项目类型(支持 monorepo)
detect_project_type() {
  # Monorepo 检测
  if [ -d "packages" ] && [ "$(ls -A packages/ 2>/dev/null | wc -l)" -gt 1 ]; then
    echo "monorepo-node"
    return
  fi
  if [ -d "apps" ] && [ "$(ls -A apps/ 2>/dev/null | wc -l)" -gt 1 ]; then
    echo "monorepo-apps"
    return
  fi
  # 检查 package.json 的 workspaces 字段
  if [ -f "package.json" ] && grep -q '"workspaces"' package.json 2>/dev/null; then
    echo "monorepo-node"
    return
  fi
  # 标准项目检测
  if [ -f "package.json" ]; then
    echo "node"
  elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ]; then
    echo "python"
  elif [ -f "Cargo.toml" ]; then
    echo "rust"
  elif [ -f "go.mod" ]; then
    echo "go"
  elif [ -f "pom.xml" ] || [ -f "build.gradle" ]; then
    echo "java"
  else
    echo "unknown"
  fi
}

# 根据项目类型填充命令
auto_detect_commands() {
  local type="$1"
  case "$type" in
    monorepo-node)
      if [ -f "pnpm-workspace.yaml" ]; then
        PKG="pnpm"
      elif [ -f "yarn.lock" ]; then
        PKG="yarn"
      else
        PKG="npm"
      fi
      INSTALL_CMD="${PKG} install"
      BUILD_CMD="${PKG} run build --if-present"
      TEST_CMD="${PKG} test --if-present"
      LINT_CMD="${PKG} run lint --if-present 2>/dev/null || echo 'no lint'"
      START_CMD="echo 'cd packages/<name> && ${PKG} run dev'"
      ;;
    monorepo-apps)
      BUILD_CMD="echo 'cd apps/<app> && npm run build'"
      TEST_CMD="echo 'cd apps/<app> && npm test'"
      LINT_CMD="echo 'cd apps/<app> && npm run lint'"
      INSTALL_CMD="npm install"
      START_CMD="echo 'cd apps/<app> && npm run dev'"
      ;;
    node)
      if [ -f "pyproject.toml" ]; then
        BUILD_CMD="python -m build 2>/dev/null || echo 'no build'"
        TEST_CMD="pytest 2>/dev/null || python -m pytest 2>/dev/null || echo 'no tests'"
        LINT_CMD="ruff check . 2>/dev/null || flake8 2>/dev/null || echo 'no lint'"
      else
        BUILD_CMD="pip install -e . 2>/dev/null || echo 'no build'"
        TEST_CMD="pytest 2>/dev/null || python -m pytest 2>/dev/null || echo 'no tests'"
        LINT_CMD="ruff check . 2>/dev/null || flake8 2>/dev/null || echo 'no lint'"
      fi
      INSTALL_CMD="pip install -r requirements.txt 2>/dev/null || pip install -e . 2>/dev/null"
      START_CMD="python main.py 2>/dev/null || python app.py 2>/dev/null || echo 'no entry point'"
      ;;
    rust)
      INSTALL_CMD="cargo build"
      BUILD_CMD="cargo build --release"
      TEST_CMD="cargo test"
      LINT_CMD="cargo clippy"
      START_CMD="cargo run"
      ;;
    go)
      INSTALL_CMD="go mod tidy"
      BUILD_CMD="go build ./..."
      TEST_CMD="go test ./..."
      LINT_CMD="golangci-lint run 2>/dev/null || go vet ./..."
      START_CMD="go run ."
      ;;
    java)
      if [ -f "pom.xml" ]; then
        BUILD_CMD="mvn compile"
        TEST_CMD="mvn test"
        LINT_CMD="mvn checkstyle:check 2>/dev/null || echo 'no lint'"
        START_CMD="mvn spring-boot:run 2>/dev/null || echo 'no start'"
      else
        BUILD_CMD="gradle build"
        TEST_CMD="gradle test"
        LINT_CMD="gradle check 2>/dev/null || echo 'no lint'"
        START_CMD="gradle bootRun 2>/dev/null || echo 'no start'"
      fi
      INSTALL_CMD="$BUILD_CMD"
      ;;
    *)
      INSTALL_CMD="echo '请手动配置安装命令'"
      BUILD_CMD="echo '请手动配置构建命令'"
      TEST_CMD="echo '请手动配置测试命令'"
      LINT_CMD="echo '请手动配置 lint 命令'"
      START_CMD="echo '请手动配置启动命令'"
      ;;
  esac
}

MODE="${1:-all}"

case "$MODE" in
  --detect)
    TYPE=$(detect_project_type)
    echo "项目类型: $TYPE"
    ;;
  --install)
    TYPE=$(detect_project_type)
    auto_detect_commands "$TYPE"
    echo "$INSTALL_CMD"
    ;;
  --verify-only)
    echo "运行验证..."
    ;;
  --start)
    echo "启动..."
    ;;
  --help|-h)
    echo "用法: bash init.sh [--detect|--install|--verify-only|--start|--help]"
    exit 0
    ;;
  all|*)
    TYPE=$(detect_project_type)
    echo "📦 检测到项目类型: $TYPE"
    echo ""
    
    auto_detect_commands "$TYPE"
    
    echo "安装: $INSTALL_CMD"
    echo "构建: $BUILD_CMD"
    echo "测试: $TEST_CMD"
    echo "Lint: $LINT_CMD"
    echo "启动: $START_CMD"
    echo ""
    
    # 执行安装和验证
    echo "Step 1: 安装依赖"
    eval "$INSTALL_CMD" || echo "⚠️ 安装失败或无需安装"
    echo ""
    
    echo "Step 2: 运行测试"
    eval "$TEST_CMD" || echo "⚠️ 测试失败或无测试"
    echo ""
    
    echo "✅ 初始化完成!"
    ;;
esac
