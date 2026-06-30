#!/bin/bash
# deploy.sh - Karakeep 一键部署脚本
# 用法: ./deploy.sh [rebuild|status|backup|restart|logs]
set -e

SRC=/home/ubuntu/src
PROD=/opt/karakeep/apps/web
DATA=/var/lib/karakeep/data
HEALTH=http://127.0.0.1:3000/api/health
BACKUP_DIR=/home/ubuntu/backups

color() { echo -e "\033[1;36m$1\033[0m"; }
ok()   { echo -e "\033[1;32m✓ $1\033[0m"; }
fail() { echo -e "\033[1;31m✗ $1\033[0m"; exit 1; }

cmd=${1:-status}

case "$cmd" in
  rebuild)
    color "=== 1. 拉取最新代码 ==="
    cd "$SRC"
    git pull 2>&1 | tail -3

    color "=== 2. 安装依赖 ==="
    pnpm install --frozen-lockfile --network-concurrency 1 --ignore-scripts 2>&1 | tail -3

    color "=== 3. 构建 web ==="
    cd "$SRC/apps/web"
    pnpm exec next build 2>&1 | tail -5

    color "=== 4. 同步产物到生产目录 ==="
    STANDALONE="$SRC/apps/web/.next/standalone/apps/web"

    # server.js
    cp -f "$STANDALONE/server.js" "$PROD/server.js"

    # .next/static (symlink covers it; ignore if standalone has no copy)
    [ -d "$STANDALONE/.next/static" ] && cp -rn "$STANDALONE/.next/static/." "$PROD/.next/static/" || true

    # node_modules 增量同步（保留硬链接）
    rsync -a "$SRC/node_modules/" "$PROD/node_modules/" 2>/dev/null || true

    color "=== 5. 重启服务 ==="
    sudo systemctl restart karakeep
    sleep 5

    if curl -sf "$HEALTH" > /dev/null 2>&1; then
      ok "部署成功! $(curl -s $HEALTH)"
    else
      fail "服务未就绪"
    fi
    ;;

  restart)
    color "=== 重启 karakeep ==="
    sudo systemctl restart karakeep
    sleep 4
    if curl -sf "$HEALTH" > /dev/null 2>&1; then
      ok "运行正常 $(curl -s $HEALTH)"
    else
      fail "服务异常"
    fi
    ;;

  status)
    echo "--- 服务状态 ---"
    sudo systemctl is-active karakeep && echo "karakeep: active" || echo "karakeep: DOWN"
    sudo docker inspect --format '{{.State.Status}}' meilisearch 2>/dev/null && echo "meilisearch: running" || echo "meilisearch: unknown"
    echo ""
    echo "--- 健康检查 ---"
    curl -s "$HEALTH" 2>/dev/null || echo "karakeep: unreachable"
    curl -s http://127.0.0.1:7700/health 2>/dev/null || echo "meilisearch: unreachable"
    echo ""
    echo "--- 磁盘 ---"
    df -h / | tail -1
    echo ""
    echo "--- 内存 ---"
    free -h | head -2
    ;;

  backup)
    mkdir -p "$BACKUP_DIR"
    BACKUP="$BACKUP_DIR/karakeep_$(date +%Y%m%d_%H%M%S).tar.gz"
    color "=== 备份数据 ==="
    sudo tar czf "$BACKUP" -C "$DATA" .
    echo "备份文件: $BACKUP ($(du -h "$BACKUP" | cut -f1))"
    ok "备份完成"
    # 保留最近 7 天
    ls -t "$BACKUP_DIR"/karakeep_*.tar.gz 2>/dev/null | tail -n +8 | xargs rm -f 2>/dev/null || true
    ;;

  logs)
    sudo journalctl -u karakeep --no-pager -n 50 --since "1 hour ago" 2>/dev/null
    ;;

  *)
    echo "用法: $0 {rebuild|restart|status|backup|logs}"
    exit 1
    ;;
esac
