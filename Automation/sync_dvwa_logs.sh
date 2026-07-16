#!/usr/bin/env bash
set -u

CONTAINER="dvwa"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$REPO_ROOT/Monitoring/dvwa-logs"
POLL_SECONDS="${DVWA_LOG_SYNC_INTERVAL:-2}"
STOP_REQUESTED=0

status() { printf '[dvwa-log-sync] %s\n' "$*"; }
error() { printf '[dvwa-log-sync] ERROR: %s\n' "$*" >&2; }

cleanup() {
  STOP_REQUESTED=1
  status "Stop requested; finishing cleanly."
}
trap cleanup INT TERM

if ! command -v docker >/dev/null 2>&1; then
  error "Docker is not available in PATH."
  exit 1
fi
if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  error "Container '$CONTAINER' does not exist."
  exit 1
fi
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" != "true" ]; then
  error "Container '$CONTAINER' is not running."
  exit 1
fi
if ! [[ "$POLL_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  error "DVWA_LOG_SYNC_INTERVAL must be a positive integer."
  exit 1
fi

mkdir -p "$LOG_DIR"

sync_one() {
  local name="$1" remote="$2"
  local output="$LOG_DIR/$name.log" state="$LOG_DIR/$name.offset"
  local remote_size offset count

  if ! remote_size="$(docker exec "$CONTAINER" stat -c '%s' "$remote" 2>/dev/null)"; then
    error "Cannot read $remote inside '$CONTAINER'."
    return 1
  fi
  if ! [[ "$remote_size" =~ ^[0-9]+$ ]]; then
    error "Unexpected size returned for $remote."
    return 1
  fi

  offset=0
  if [ -f "$state" ]; then
    read -r offset < "$state" || offset=0
    [[ "$offset" =~ ^[0-9]+$ ]] || offset=0
  fi
  if (( remote_size < offset )); then
    status "$name.log was rotated or truncated; resuming at byte 0."
    offset=0
  fi

  count=$((remote_size - offset))
  if (( count > 0 )); then
    if docker exec "$CONTAINER" sh -c \
      'dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null' sh \
      "$remote" "$offset" "$count" >> "$output"; then
      printf '%s\n' "$remote_size" > "$state"
      status "Appended $count byte(s) to $name.log."
    else
      error "Failed to synchronize $remote."
      return 1
    fi
  else
    touch "$output"
  fi
}

status "Synchronizing Apache logs from '$CONTAINER' every $POLL_SECONDS second(s)."
status "Destination: $LOG_DIR"
status "Press Ctrl+C to stop."

while (( STOP_REQUESTED == 0 )); do
  if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)" != "true" ]; then
    error "Container '$CONTAINER' is no longer running; stopping."
    exit 1
  fi
  sync_one access /var/log/apache2/access.log || true
  sync_one error /var/log/apache2/error.log || true
  sleep "$POLL_SECONDS" &
  wait $! || true
done

status "Synchronization stopped."
