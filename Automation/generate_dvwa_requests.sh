#!/usr/bin/env bash
set -u

URL="http://127.0.0.1:8080/login.php"
COUNT="${1:-10}"

if ! command -v curl >/dev/null 2>&1; then
  printf '[dvwa-test] ERROR: curl is not available.\n' >&2
  exit 1
fi
if ! [[ "$COUNT" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Usage: %s [positive-request-count]\n' "$0" >&2
  exit 2
fi
if ! curl --silent --show-error --fail --output /dev/null --max-time 5 "$URL"; then
  printf '[dvwa-test] ERROR: DVWA is unreachable at %s; no test batch was sent.\n' "$URL" >&2
  exit 1
fi

printf '[dvwa-test] Creating authorized local lab telemetry: %s request(s) to %s\n' "$COUNT" "$URL"
for ((i = 1; i <= COUNT; i++)); do
  if ! curl --silent --show-error --output /dev/null --max-time 5 "$URL"; then
    printf '[dvwa-test] ERROR: Request %s failed; stopping.\n' "$i" >&2
    exit 1
  fi
done
printf '[dvwa-test] Completed %s authorized local request(s).\n' "$COUNT"
