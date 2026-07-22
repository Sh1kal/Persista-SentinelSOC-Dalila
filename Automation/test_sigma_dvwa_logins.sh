#!/usr/bin/env bash
set -euo pipefail

URL="${DVWA_LOGIN_URL:-http://127.0.0.1:8080/login.php}"
COUNT="${1:-5}"
COOKIE_FILE="$(mktemp /tmp/sentinelsoc-sigma-cookie.XXXXXX)"
PAGE_FILE="$(mktemp /tmp/sentinelsoc-sigma-page.XXXXXX)"
cleanup() { rm -f "$COOKIE_FILE" "$PAGE_FILE"; }
trap cleanup EXIT

fail() { printf '[sigma-test] ERROR: %s\n' "$*" >&2; exit 1; }
[[ "$COUNT" =~ ^[1-9][0-9]*$ ]] || fail "Count must be a positive integer."
command -v curl >/dev/null 2>&1 || fail "curl is not available."

for ((attempt = 1; attempt <= COUNT; attempt++)); do
  curl --silent --show-error --fail --max-time 5 \
    --cookie "$COOKIE_FILE" --cookie-jar "$COOKIE_FILE" \
    --output "$PAGE_FILE" "$URL"
  token="$(sed -n "s/.*name='user_token' value='\([^']*\)'.*/\1/p" "$PAGE_FILE" | head -n 1)"
  [ -n "$token" ] || fail "Could not obtain the DVWA CSRF token."

  curl --silent --show-error --max-time 5 \
    --cookie "$COOKIE_FILE" --cookie-jar "$COOKIE_FILE" \
    --output "$PAGE_FILE" \
    --data-urlencode "username=sigma-harmless-test" \
    --data-urlencode "password=definitely-wrong" \
    --data-urlencode "Login=Login" \
    --data-urlencode "user_token=$token" \
    "$URL"
  printf '[sigma-test] Harmless failed login %d/%d sent.\n' "$attempt" "$COUNT"
done
