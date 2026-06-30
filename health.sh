#!/bin/bash
# /home/ubuntu/health.sh — Karakeep 系统健康快照
# 用法: /home/ubuntu/health.sh
set -euo pipefail

ok()  { printf '\033[1;32m  ✓ %s\033[0m\n' "$1"; }
bad() { printf '\033[1;31m  ✗ %s\033[0m\n' "$1"; }

echo "═══ SYSTEM ═══"
echo "  host:      $(hostname)"
echo "  uptime:    $(uptime -p)"
echo "  disk:      $(df -h / | awk 'NR==2{printf "%s / %s (%s used)", $3, $2, $5}')"
echo "  mem:       $(free -h | awk 'NR==2{printf "%s / %s (avail %s)", $3, $2, $7}')"

echo ""
echo "═══ SERVICES ═══"
check_svc() {
  local name="$1" type="$2" cmd="$3"
  if eval "$cmd" >/dev/null 2>&1; then
    ok "$name ($type)"
  else
    bad "$name ($type) — DOWN"
  fi
}
check_svc karakeep  systemd  "systemctl is-active karakeep"
check_svc meilisearch docker   "docker inspect --format '{{.State.Status}}' meilisearch | grep -q running"
check_svc nginx     systemd  "systemctl is-active nginx"
check_svc cron      systemd  "systemctl is-active cron"

echo ""
echo "═══ PORTS ═══"
ss -tlnp 2>/dev/null | awk 'NR>1 && /:3000 |:7700 |:3001 |:80 |:22 /{print "  "$5}' | sed 's/:.*//' | sort -u

echo ""
echo "═══ HEALTH ENDPOINTS ═══"
hc() { curl -sf "$1" 2>/dev/null | head -1 && return 0; printf '  \033[1;31m✗ %s unreachable\033[0m\n' "$2"; }
hc http://127.0.0.1:3000/api/health karakeep
hc http://127.0.0.1:7700/health     meilisearch

echo ""
echo "═══ RECENT LOGS (karakeep, last 10 lines) ═══"
sudo journalctl -u karakeep --no-pager -n 10 --since "10 minutes ago" 2>/dev/null || echo "  (no journal)"

echo ""
echo "═══ LAST DEPLOY ═══"
cd /home/ubuntu/src 2>/dev/null && git log --oneline -1 || echo "  no git repo"

echo ""
echo "═══ LAST BACKUP ═══"
latest=$(ls -t /home/ubuntu/backups/karakeep_*.tar.gz 2>/dev/null | head -1)
if [ -n "$latest" ]; then
  echo "  $latest ($(du -h "$latest" | cut -f1))"
else
  bad "no backup found"
fi

echo ""
echo "═══ DISK TOP CONSUMERS ═══"
du -sh /* 2>/dev/null | sort -rh | head -5
