#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
RUNTIME_DIR="$REPO_ROOT/Monitoring/dvwa-logs"
PID_FILE="$RUNTIME_DIR/dvwa-log-sync.pid"
OUTPUT_FILE="$RUNTIME_DIR/sync.log"

mkdir -p "$RUNTIME_DIR"
if [ -f "$PID_FILE" ]; then
  read -r old_pid < "$PID_FILE" || old_pid=""
  if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
    printf '[dvwa-log-sync] Already running with PID %s.\n' "$old_pid"
    exit 0
  fi
  printf '[dvwa-log-sync] Replacing stale PID file.\n'
fi

nohup "$SCRIPT_DIR/sync_dvwa_logs.sh" >> "$OUTPUT_FILE" 2>&1 &
sync_pid=$!
printf '%s\n' "$sync_pid" > "$PID_FILE"
sleep 1
if kill -0 "$sync_pid" 2>/dev/null; then
  printf '[dvwa-log-sync] Started with PID %s. Output: %s\n' "$sync_pid" "$OUTPUT_FILE"
else
  printf '[dvwa-log-sync] ERROR: Process failed to start; inspect %s.\n' "$OUTPUT_FILE" >&2
  rm -f "$PID_FILE"
  exit 1
fi
