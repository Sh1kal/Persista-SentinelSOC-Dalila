#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ACCESS_LOG="$REPO_ROOT/Monitoring/dvwa-logs/access.log"
ERROR_LOG="$REPO_ROOT/Monitoring/dvwa-logs/error.log"
CONFIG="/var/ossec/etc/ossec.conf"
OSSEC_LOG="/var/ossec/logs/ossec.log"
failures=0

pass() { printf '[PASS] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; failures=$((failures + 1)); }

if command -v docker >/dev/null 2>&1 && docker inspect dvwa >/dev/null 2>&1; then
  if [ "$(docker inspect -f '{{.State.Running}}' dvwa 2>/dev/null)" = true ]; then pass "DVWA container is running."; else fail "DVWA container exists but is not running."; fi
else
  fail "Docker is unavailable or the DVWA container does not exist."
fi
if curl --silent --show-error --output /dev/null --max-time 5 http://127.0.0.1:8080/login.php; then pass "DVWA HTTP endpoint is available."; else fail "DVWA HTTP endpoint is unavailable."; fi
if docker exec dvwa test -f /var/log/apache2/access.log 2>/dev/null; then pass "Apache access log exists inside DVWA."; else fail "Apache access log is missing inside DVWA."; fi
if [ -f "$ACCESS_LOG" ]; then
  pass "Host access log exists: $ACCESS_LOG"
  if latest="$(stat -c '%y' "$ACCESS_LOG" 2>/dev/null)"; then printf '[INFO] Latest host access-log timestamp: %s\n' "$latest"; fi
else
  fail "Host access log does not exist: $ACCESS_LOG"
fi

if [ -f "$CONFIG" ]; then pass "Wazuh agent configuration exists (agent appears installed)."; else fail "Wazuh agent configuration is absent: $CONFIG"; fi
if systemctl list-unit-files wazuh-agent.service --no-legend 2>/dev/null | grep -q wazuh-agent; then
  if systemctl is-active --quiet wazuh-agent; then pass "wazuh-agent service is active."; else fail "wazuh-agent is installed but not active."; fi
else
  fail "wazuh-agent service is not installed."
fi
if [ -r "$CONFIG" ] && grep -Fq "$ACCESS_LOG" "$CONFIG" && grep -Fq "$ERROR_LOG" "$CONFIG"; then
  pass "ossec.conf contains both DVWA log paths."
else
  fail "ossec.conf does not contain both DVWA log paths."
fi
if [ -r "$OSSEC_LOG" ] && grep -F 'Analyzing file:' "$OSSEC_LOG" | grep -Fq "$ACCESS_LOG" && grep -F 'Analyzing file:' "$OSSEC_LOG" | grep -Fq "$ERROR_LOG"; then
  pass "Wazuh logcollector reports monitoring both DVWA files."
else
  warn "No logcollector monitoring records for both DVWA files were found in $OSSEC_LOG."
fi

if (( failures > 0 )); then
  printf '[SUMMARY] %s required check(s) failed.\n' "$failures"
  exit 1
fi
printf '[SUMMARY] All required checks passed.\n'
