#!/bin/bash
# ============================================================
# 本地 Docker 构建 + 部署 — 适用于正式落地
# 触发条件: schema 变更, 依赖变更, Next.js 前端, Dockerfile 改动
#
# 用法:
#   bash scripts/build-deploy.sh          # 构建 aio 并部署
#   bash scripts/build-deploy.sh --push   # 构建并推送到 ghcr.io
# ============================================================
set -euo pipefail

SERVER="${KARAKEEP_SERVER:-ubuntu@124.222.143.123}"
COMPOSE_DIR="${KARAKEEP_COMPOSE_DIR:-/home/ubuntu/karakeep}"
IMAGE="karakeep-custom:local"
REMOTE_TAG="karakeep-custom:latest"

echo "=== Step 1: Build Docker image (aio/amd64) ==="
docker build \
  -f docker/Dockerfile \
  --target aio \
  --platform linux/amd64 \
  -t "$IMAGE" .

echo "=== Step 2: Save + compress ==="
LOCAL_TAR="/tmp/karakeep-build.tar.gz"
docker save "$IMAGE" | gzip > "$LOCAL_TAR"
echo "  Size: $(ls -lh "$LOCAL_TAR" | awk '{print $5}')"

echo "=== Step 3: SCP to server ==="
scp "$LOCAL_TAR" "$SERVER:/tmp/karakeep-build.tar.gz"

echo "=== Step 4: Load + deploy ==="
ssh "$SERVER" "
  set -euo pipefail
  gunzip -f /tmp/karakeep-build.tar.gz
  docker load -i /tmp/karakeep-build.tar
  docker tag $IMAGE $REMOTE_TAG
  cd $COMPOSE_DIR && docker compose up -d --no-deps --force-recreate web
  rm -f /tmp/karakeep-build.tar /tmp/karakeep-build.tar.gz
"

echo "=== Step 5: Health check ==="
sleep 10
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://124.222.143.123:3000/api/health)
if [ "$HTTP_CODE" = "200" ]; then
  echo "  ✅ Health check: HTTP $HTTP_CODE"
else
  echo "  ❌ Health check: HTTP $HTTP_CODE"
  echo "  回滚: ssh $SERVER 'cd $COMPOSE_DIR && docker compose up -d --no-deps --force-recreate web'"
  exit 1
fi

echo "=== Step 6: Cleanup ==="
rm -f "$LOCAL_TAR"
echo "  Done"

echo ""
echo "🎉 Build & Deploy complete!"
