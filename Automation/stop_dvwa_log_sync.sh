#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PID_FILE="$REPO_ROOT/Monitoring/dvwa-logs/dvwa-log-sync.pid"

if [ ! -f "$PID_FILE" ]; then
  printf '[dvwa-log-sync] No PID file found; synchronization is not recorded as running.\n'
  exit 0
fi
read -r sync_pid < "$PID_FILE" || sync_pid=""
if ! [[ "$sync_pid" =~ ^[0-9]+$ ]]; then
  printf '[dvwa-log-sync] ERROR: Invalid PID file: %s\n' "$PID_FILE" >&2
  exit 1
fi
if ! kill -0 "$sync_pid" 2>/dev/null; then
  printf '[dvwa-log-sync] Process %s is not running; removing stale PID file.\n' "$sync_pid"
  rm -f "$PID_FILE"
  exit 0
fi
if [ -r "/proc/$sync_pid/cmdline" ] && ! tr '\0' ' ' < "/proc/$sync_pid/cmdline" | grep -Fq 'sync_dvwa_logs.sh'; then
  printf '[dvwa-log-sync] ERROR: PID %s does not appear to be the sync process; refusing to stop it.\n' "$sync_pid" >&2
  exit 1
fi

kill -TERM "$sync_pid"
for _ in {1..20}; do
  if ! kill -0 "$sync_pid" 2>/dev/null; then
    rm -f "$PID_FILE"
    printf '[dvwa-log-sync] Stopped cleanly.\n'
    exit 0
  fi
  sleep 0.25
done
printf '[dvwa-log-sync] ERROR: Process %s did not stop; PID file retained.\n' "$sync_pid" >&2
exit 1
