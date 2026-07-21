#!/usr/bin/env bash
# schedule-loop.sh — Scheduler integration for MCF self-improvement loop
# Triggers the self-improvement loop on a schedule (cron/launchd/systemd)
#
# Usage:
#   schedule-loop.sh install <schedule>   # Install scheduler entry
#   schedule-loop.sh run                  # Run the loop (called by scheduler)
#   schedule-loop.sh status               # Show scheduler status
#   schedule-loop.sh remove               # Remove scheduler entry
#
# Schedules: hourly, daily, weekly, or cron expression
#
# Reference: ArchiveExplorer "Loop and Harness engineering" — Step 4: Scheduler & persistence

set -uo pipefail

FWK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOP_SCRIPT="${FWK_DIR}/self-improve/self-improve.sh"
LOG_DIR="${FWK_DIR}/.memory/scheduler-logs"
STATE_FILE="${FWK_DIR}/.memory/.scheduler-state.json"

mkdir -p "$LOG_DIR"

# ── Run (called by scheduler) ───────────────────────────────────────────────
run_loop() {
  local run_id
  run_id="$(date -u +%Y%m%d_%H%M%S)"
  local log_file="${LOG_DIR}/run_${run_id}.log"
  
  echo "{\"last_run\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"status\": \"running\", \"run_id\": \"${run_id}\"}" > "$STATE_FILE"
  
  echo "═══ MCF Self-Improvement Loop — Scheduled Run ${run_id} ═══"
  echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Log: ${log_file}"
  echo ""
  
  # Run the loop, capture output
  if bash "$LOOP_SCRIPT" > "$log_file" 2>&1; then
    echo "{\"last_run\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"status\": \"completed\", \"run_id\": \"${run_id}\", \"log\": \"${log_file}\"}" > "$STATE_FILE"
    echo "✅ Loop completed successfully"
  else
    local rc=$?
    echo "{\"last_run\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"status\": \"failed\", \"run_id\": \"${run_id}\", \"rc\": ${rc}, \"log\": \"${log_file}\"}" > "$STATE_FILE"
    echo "❌ Loop failed with exit code ${rc}"
    echo "Check log: ${log_file}"
    return $rc
  fi
}

# ── Install ─────────────────────────────────────────────────────────────────
install_schedule() {
  local schedule="${1:-daily}"
  local dry_run="${2:-false}"
  
  case "$(uname -s)" in
    Darwin)
      install_launchd "$schedule" "$dry_run"
      ;;
    Linux)
      install_systemd_or_cron "$schedule" "$dry_run"
      ;;
    *)
      echo "⚠️  Unsupported OS: $(uname -s). Use cron manually:"
      echo "   bash ${FWK_DIR}/schedule-loop.sh run"
      return 1
      ;;
  esac
}

install_launchd() {
  local schedule="$1"
  local dry_run="${2:-false}"
  if [[ "$dry_run" == "true" ]]; then
    echo "🔍 DRY RUN: Would create ${plist_file}"
    echo "   Schedule: every ${interval}s (${schedule})"
    echo "   Command: bash ${FWK_DIR}/schedule-loop.sh run"
    return 0
  fi
  local plist_name="com.mcf.self-improve"
  local plist_file="${HOME}/Library/LaunchAgents/${plist_name}.plist"
  
  # Convert schedule to StartInterval
  local interval=86400  # default daily
  case "$schedule" in
    hourly) interval=3600 ;;
    daily)  interval=86400 ;;
    weekly) interval=604800 ;;
    *)      if [[ "$schedule" =~ ^[0-9]+$ ]]; then
              interval="$schedule"
            else
              echo "❌ Invalid interval: '${schedule}' is not numeric (seconds)" >&2
              return 1
            fi
            ;;
  esac
  cat > "$plist_file" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${plist_name}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/env</string>
        <string>bash</string>
        <string>${FWK_DIR}/schedule-loop.sh</string>
        <string>run</string>
    </array>
    <key>StartInterval</key>
    <integer>${interval}</integer>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/launchd_out.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/launchd_err.log</string>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
PLIST
  
  # Load the agent
  launchctl unload "$plist_file" 2>/dev/null || true
  launchctl load "$plist_file"
  
  echo "✅ LaunchAgent installed: ${plist_file}"
  echo "   Schedule: every ${interval}s (${schedule})"
  echo "   Logs: ${LOG_DIR}/"
  echo ""
  echo "Commands:"
  echo "  launchctl start ${plist_name}    # run now"
  echo "  launchctl stop ${plist_name}     # stop"
  echo "  launchctl unload ${plist_file}   # disable"
}

install_systemd_or_cron() {
  local schedule="$1"
  
  # Try systemd user timer first
  if command -v systemctl &>/dev/null && [[ -d "${HOME}/.config/systemd/user" ]]; then
    install_systemd "$schedule"
  else
    install_cron "$schedule"
  fi
}

install_systemd() {
  local schedule="$1"
  local unit_dir="${HOME}/.config/systemd/user"
  mkdir -p "$unit_dir"
  
  # Convert schedule
  local on_calendar="daily"
  case "$schedule" in
    hourly) on_calendar="hourly" ;;
    daily)  on_calendar="daily" ;;
    weekly) on_calendar="weekly" ;;
  esac
  
  cat > "${unit_dir}/mcf-self-improve.service" << SVC
[Unit]
Description=MCF Self-Improvement Loop
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash ${FWK_DIR}/schedule-loop.sh run
WorkingDirectory=${FWK_DIR}

[Install]
WantedBy=default.target
SVC

  cat > "${unit_dir}/mcf-self-improve.timer" << TMR
[Unit]
Description=Run MCF Self-Improvement Loop ${schedule}

[Timer]
OnCalendar=${on_calendar}
Persistent=true

[Install]
WantedBy=timers.target
TMR

  systemctl --user daemon-reload
  systemctl --user enable mcf-self-improve.timer
  systemctl --user start mcf-self-improve.timer
  
  echo "✅ Systemd timer installed"
  echo "   Schedule: ${on_calendar}"
  echo "   Check: systemctl --user status mcf-self-improve.timer"
}

install_cron() {
  local schedule="$1"
  local cron_expr="0 9 * * *"  # default daily 9am
  
  case "$schedule" in
    hourly) cron_expr="0 * * * *" ;;
    daily)  cron_expr="0 9 * * *" ;;
    weekly) cron_expr="0 9 * * 1" ;;
  esac
  
  local cron_entry="${cron_expr} cd ${FWK_DIR} && bash ${FWK_DIR}/schedule-loop.sh run >> ${LOG_DIR}/cron.log 2>&1"
  
  # Add to crontab (avoiding duplicates)
  (crontab -l 2>/dev/null | grep -v "schedule-loop.sh"; echo "$cron_entry") | crontab -
  
  echo "✅ Cron entry installed"
  echo "   Expression: ${cron_expr}"
  echo "   Check: crontab -l"
}

# ── Status ──────────────────────────────────────────────────────────────────
status() {
  echo "═══ MCF Scheduler Status ═══"
  echo ""
  
  if [[ -f "$STATE_FILE" ]]; then
    cat "$STATE_FILE"
  else
    echo "No scheduler state found."
  fi
  
  echo ""
  
  # Check platform-specific status
  case "$(uname -s)" in
    Darwin)
      launchctl list | grep com.mcf.self-improve || echo "LaunchAgent not loaded"
      ;;
    Linux)
      systemctl --user status mcf-self-improve.timer 2>/dev/null || echo "Systemd timer not found"
      ;;
  esac
  
  echo ""
  echo "Recent logs:"
  ls -lt "$LOG_DIR" 2>/dev/null | head -5 || echo "  (none)"
}

# ── Remove ──────────────────────────────────────────────────────────────────
remove_schedule() {
  case "$(uname -s)" in
    Darwin)
      local plist_file="${HOME}/Library/LaunchAgents/com.mcf.self-improve.plist"
      launchctl unload "$plist_file" 2>/dev/null
      rm -f "$plist_file"
      echo "✅ LaunchAgent removed"
      ;;
    Linux)
      systemctl --user stop mcf-self-improve.timer 2>/dev/null
      systemctl --user disable mcf-self-improve.timer 2>/dev/null
      rm -f "${HOME}/.config/systemd/user/mcf-self-improve."{service,timer}
      systemctl --user daemon-reload
      # Also remove cron
      crontab -l 2>/dev/null | grep -v "schedule-loop.sh" | crontab -
      echo "✅ Systemd timer + cron entries removed"
      ;;
  esac
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-status}" in
  run)        run_loop ;;
  install)
    shift
    local schedule="${1:-daily}"
    local dry_run="false"
    [[ "${2:-}" == "--dry-run" ]] && dry_run="true"
    install_schedule "$schedule" "$dry_run"
    ;;
  status)     status ;;
  remove)     remove_schedule ;;
  *)          echo "Usage: schedule-loop.sh {run|install <schedule> [--dry-run]|status|remove}" ;;
esac
