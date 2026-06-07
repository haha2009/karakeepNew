#!/bin/bash
# ============================================================
# 快速热修复 — 本地 build → SCP → docker cp → 重启
# 适用于: workers, CLI 等纯 JS 改动
# 不适用于: schema 变更, 依赖变更, Next.js 前端
#
# 用法:
#   bash scripts/hotfix.sh workers    # 只热修 workers
#   bash scripts/hotfix.sh cli        # 只热修 CLI
#   bash scripts/hotfix.sh all        # 热修所有
# ============================================================
set -euo pipefail

SERVER="${KARAKEEP_SERVER:-ubuntu@124.222.143.123}"
COMPOSE_DIR="${KARAKEEP_COMPOSE_DIR:-/home/ubuntu/karakeep}"
CONTAINER="${KARAKEEP_CONTAINER:-karakeep-web-1}"
HOTFIX_DIR="/tmp/karakeep-hotfix"

TARGET="${1:-workers}"
shift 2>/dev/null || true

hotfix_workers() {
  echo "=== [hotfix] Building workers ==="
  pnpm build --filter @karakeep/workers

  echo "=== [hotfix] Packaging dist/ ==="
  rm -rf "$HOTFIX_DIR/workers"
  mkdir -p "$HOTFIX_DIR/workers"
  cp -r apps/workers/dist/* "$HOTFIX_DIR/workers/"

  echo "=== [hotfix] Backing up remote dist/ ==="
  ssh "$SERVER" "docker exec $CONTAINER mkdir -p /tmp/workers-backup"
  ssh "$SERVER" "docker cp $CONTAINER:/app/apps/workers/dist/. /tmp/workers-backup/" 2>/dev/null || true

  echo "=== [hotfix] SCP → docker cp ==="
  scp -r "$HOTFIX_DIR/workers" "$SERVER:/tmp/workers-dist-new"
  ssh "$SERVER" "docker cp /tmp/workers-dist-new/. $CONTAINER:/app/apps/workers/dist/
rm -rf /tmp/workers-dist-new"

  echo "=== [hotfix] Restarting container ==="
  ssh "$SERVER" "docker restart $CONTAINER"

  echo "=== [hotfix] Health check ==="
  sleep 5
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://124.222.143.123:3000/api/health)
  if [ "$HTTP_CODE" = "200" ]; then
    echo "  ✅ Health check: HTTP $HTTP_CODE"
  else
    echo "  ❌ Health check: HTTP $HTTP_CODE"
    echo "  回滚: ssh $SERVER 'docker cp /tmp/workers-backup/. $CONTAINER:/app/apps/workers/dist/ && docker restart $CONTAINER'"
    exit 1
  fi
}

hotfix_cli() {
  echo "=== [hotfix] Building CLI ==="
  pnpm build --filter @karakeep/cli

  echo "=== [hotfix] SCP → docker cp ==="
  scp apps/cli/dist/index.mjs "$SERVER:/tmp/cli-index.mjs"
  ssh "$SERVER" "docker cp /tmp/cli-index.mjs $CONTAINER:/app/apps/cli/index.mjs"

  echo "  ✅ CLI hotfixed"
}

case "$TARGET" in
  workers)
    hotfix_workers
    ;;
  cli)
    hotfix_cli
    ;;
  all)
    hotfix_workers
    hotfix_cli
    ;;
  *)
    echo "用法: $0 {workers|cli|all}"
    exit 1
    ;;
esac

echo "🎉 Hotfix complete!"
