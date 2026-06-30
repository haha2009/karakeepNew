#!/bin/bash
# deploy.sh - Karakeep 一键部署脚本
# 用法: ./deploy.sh [rebuild|restart|status|backup|logs|rollback]
set -euo pipefail

SRC=/home/ubuntu/src
PROD=/opt/karakeep/apps/web
DATA=/var/lib/karakeep/data
HEALTH=http://127.0.0.1:3000/api/health
BACKUP_DIR=/home/ubuntu/backups

color() { echo -e "\033[1;36m$1\033[0m"; }
ok()   { echo -e "\033[1;32m✓ $1\033[0m"; }
fail() { echo -e "\033[1;31m✗ $1\033[0m"; exit 1; }

cmd=${1:-help}

prev_commit() {
  cd "$SRC"
  git log --oneline -5 2>/dev/null | awk 'NR==1{print $1}'
}

case "$cmd" in
  rebuild)
    color "=== 0. 部署前备份 (门控) ==="
    mkdir -p "$BACKUP_DIR"
    "$0" backup

    color "=== 1. 拉取最新代码 ==="
    cd "$SRC"
    git pull 2>&1 | tail -3

    color "=== 2. 安装依赖 ==="
    pnpm install --frozen-lockfile --ignore-scripts 2>&1 | tail -3

    color "=== 3. 构建 web ==="
    cd "$SRC/apps/web"
    pnpm exec next build 2>&1 | tail -5

    color "=== 4. 同步产物到生产目录 ==="
    STANDALONE="$SRC/apps/web/.next/standalone/apps/web"
    cp -f "$STANDALONE/server.js" "$PROD/server.js"

    color "=== 5. 重启服务 ==="
    sudo systemctl restart karakeep
    sleep 5

    if curl -sf "$HEALTH" > /dev/null 2>&1; then
      ok "部署成功! $(curl -s $HEALTH)"
    else
      fail "服务未就绪 — 手动回滚: $0 rollback $(prev_commit)"
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

  rollback)
    commit=${1:?用法: $0 rollback <git-commit>}
    color "=== 回滚到 $commit ==="
    cd "$SRC"
    git checkout "$commit"
    cd apps/web && pnpm exec next build 2>&1 | tail -5
    cp -f "$SRC/apps/web/.next/standalone/apps/web/server.js" "$PROD/server.js"
    sudo systemctl restart karakeep
    sleep 4
    if curl -sf "$HEALTH" > /dev/null 2>&1; then
      ok "回滚成功 $(curl -s $HEALTH)"
    else
      fail "回滚失败"
    fi
    ;;

  status)
    echo "--- 服务状态 ---"
    systemctl is-active karakeep 2>/dev/null && echo "  karakeep: active" || echo "  karakeep: DOWN"
    docker inspect --format '{{.State.Status}}' meilisearch 2>/dev/null | grep -q running && echo "  meilisearch: running" || echo "  meilisearch: DOWN"
    echo ""
    echo "--- 健康检查 ---"
    curl -sf "$HEALTH" 2>/dev/null || echo "  karakeep: unreachable"
    curl -sf http://127.0.0.1:7700/health 2>/dev/null || echo "  meilisearch: unreachable"
    echo ""
    echo "--- 磁盘 / 内存 ---"
    df -h / | awk 'NR==2{print "  disk: "$5 " used"}'
    free -h | awk 'NR==2{print "  mem: "$3"/"$2" (avail "$7")"}'
    ;;

  backup)
    mkdir -p "$BACKUP_DIR"
    BACKUP="$BACKUP_DIR/karakeep_$(date +%Y%m%d_%H%M%S).tar.gz"
    color "=== 备份数据 ==="
    sudo tar czf "$BACKUP" -C "$DATA" .
    echo "  $BACKUP ($(du -h "$BACKUP" | cut -f1))"
    ok "备份完成"
    # 保留最近 7 天
    ls -t "$BACKUP_DIR"/karakeep_*.tar.gz 2>/dev/null | tail -n +8 | xargs rm -f 2>/dev/null || true
    ;;

  logs)
    sudo journalctl -u karakeep --no-pager -n 50 --since "1 hour ago" 2>/dev/null || echo "no logs"
    ;;

  help|*)
    cat <<'USAGE'
用法: ./deploy.sh <command>

  rebuild     git pull → install → build → sync → restart → health check
  restart     重启 karakeep 服务 (不构建)
  rollback <commit>  回滚到指定 git commit 并重建
  status      服务状态 + 健康 + 磁盘/内存
  backup      备份 /var/lib/karakeep/data/ (保留 7 天)
  logs         最近 50 行日志
  help         显示此帮助

推荐日常使用:
  ./deploy.sh status          # 先看状态
  ./deploy.sh rebuild         # 全量部署（含自动备份）
  ./deploy.sh restart         # 仅重启
USAGE
    ;;
esac
