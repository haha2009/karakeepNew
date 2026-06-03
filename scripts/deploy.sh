#!/bin/bash
set -euo pipefail

# ============================================================
# Karakeep 一键部署脚本
# 用法: bash scripts/deploy.sh
#
# 流程:
#   1. 从 ghcr.io 拉取最新 amd64 镜像 (Mac)
#   2. docker save + gzip
#   3. SCP 到腾讯云服务器
#   4. 服务器 docker load + tag + compose up
#   5. 健康检查验证
#   6. 清理本地/远程临时文件
# ============================================================

SERVER="ubuntu@124.222.143.123"
IMAGE="ghcr.io/haha2009/karakeepnew/karakeep:latest-amd64"
LOCAL_TAR="/tmp/karakeep-latest.tar.gz"
REMOTE_TAR="/home/ubuntu/karakeep-latest.tar.gz"
COMPOSE_DIR="/home/ubuntu/karakeep"
LOCAL_TAG="karakeep-custom:latest"

echo "=== Step 1: Pull latest image ==="
docker pull --platform linux/amd64 "$IMAGE"

echo "=== Step 2: Save image to tar ==="
docker save "$IMAGE" | gzip > "$LOCAL_TAR"
echo "  Saved: $(ls -lh "$LOCAL_TAR" | awk '{print $5}')"

echo "=== Step 3: SCP to server ==="
scp "$LOCAL_TAR" "$SERVER:$REMOTE_TAR"

echo "=== Step 4: Load and deploy on server ==="
ssh "$SERVER" "
  set -euo pipefail
  echo '  Loading image...'
  gunzip -c $REMOTE_TAR | docker load
  echo '  Tagging as $LOCAL_TAG...'
  docker tag $IMAGE $LOCAL_TAG
  echo '  Restarting web container...'
  cd $COMPOSE_DIR && docker compose up -d --no-deps --force-recreate web
"

echo "=== Step 5: Health check ==="
sleep 5
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://124.222.143.123:3000/api/health)
if [ "$HTTP_CODE" = "200" ]; then
  echo "  ✅ Health check passed: HTTP $HTTP_CODE"
else
  echo "  ❌ Health check failed: HTTP $HTTP_CODE"
  exit 1
fi

echo "=== Step 6: Cleanup ==="
rm -f "$LOCAL_TAR"
ssh "$SERVER" "rm -f $REMOTE_TAR"
echo "  Local and remote temp files removed"

echo ""
echo "🎉 Deploy complete! Production is running the latest image."
