#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ACCESS_LOG="$REPO_ROOT/Monitoring/dvwa-logs/access.log"
ERROR_LOG="$REPO_ROOT/Monitoring/dvwa-logs/error.log"
CONFIG="/var/ossec/etc/ossec.conf"
OSSEC_LOG="/var/ossec/logs/ossec.log"
PID_FILE="$REPO_ROOT/Monitoring/dvwa-logs/dvwa-log-sync.pid"
MAX_LOG_AGE="${DVWA_LOG_MAX_AGE_SECONDS:-300}"
failures=0
warnings=0

pass() { printf '[PASS] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf '[FAIL] %s\n' "$*"; failures=$((failures + 1)); }

if command -v docker >/dev/null 2>&1 && docker inspect dvwa >/dev/null 2>&1; then
  if [ "$(docker inspect -f '{{.State.Running}}' dvwa 2>/dev/null)" = true ]; then pass "DVWA container is running."; else fail "DVWA container exists but is not running."; fi
else
  fail "Docker is unavailable or the DVWA container does not exist."
fi
if curl --silent --show-error --output /dev/null --max-time 5 http://127.0.0.1:8080/login.php; then pass "DVWA HTTP endpoint is available."; else fail "DVWA HTTP endpoint is unavailable."; fi
if docker exec dvwa test -f /var/log/apache2/access.log 2>/dev/null; then pass "Apache access log exists inside DVWA."; else fail "Apache access log is missing inside DVWA."; fi
if [ -r "$PID_FILE" ]; then
  read -r sync_pid < "$PID_FILE" || sync_pid=""
  if [[ "$sync_pid" =~ ^[0-9]+$ ]] && kill -0 "$sync_pid" 2>/dev/null && \
     [ -r "/proc/$sync_pid/cmdline" ] && tr '\0' ' ' < "/proc/$sync_pid/cmdline" | grep -Fq 'sync_dvwa_logs.sh'; then
    pass "DVWA log synchronization is running with PID $sync_pid."
  else
    fail "DVWA log synchronization PID is stale or does not identify the sync worker."
  fi
else
  fail "DVWA log synchronization PID file is absent: $PID_FILE"
fi
if [ -f "$ACCESS_LOG" ]; then
  pass "Host access log exists: $ACCESS_LOG"
  if modified="$(stat -c '%Y' "$ACCESS_LOG" 2>/dev/null)"; then
    age=$(( $(date +%s) - modified ))
    if (( age <= MAX_LOG_AGE )); then pass "Host access log was updated recently (${age}s ago)."; else fail "Host access log is stale (${age}s old; limit ${MAX_LOG_AGE}s)."; fi
  fi
else
  fail "Host access log does not exist: $ACCESS_LOG"
fi

if dpkg-query -W -f='${Status}' wazuh-agent 2>/dev/null | grep -Fq 'install ok installed'; then pass "Wazuh Agent package is installed."; else fail "Wazuh Agent package is not installed."; fi
if systemctl list-unit-files wazuh-agent.service --no-legend 2>/dev/null | grep -q wazuh-agent; then
  if systemctl is-active --quiet wazuh-agent; then pass "wazuh-agent service is active."; else fail "wazuh-agent is installed but not active."; fi
else
  fail "wazuh-agent service is not installed."
fi
if command -v docker >/dev/null 2>&1 && \
   docker exec single-node-wazuh.manager-1 /var/ossec/bin/agent_control -lc 2>/dev/null | \
   grep -E 'Name: kali-sentinelsoc,.*Active$' >/dev/null; then
  pass "Agent kali-sentinelsoc is connected to the manager."
else
  fail "Agent kali-sentinelsoc is not reported Active by the manager."
fi
if [ -r "$CONFIG" ] && grep -Fq "$ACCESS_LOG" "$CONFIG" && grep -Fq "$ERROR_LOG" "$CONFIG"; then
  pass "ossec.conf contains both DVWA log paths."
elif [ ! -r "$CONFIG" ]; then
  warn "Cannot read $CONFIG as this user; run the verifier with sudo to check its DVWA paths."
else
  fail "ossec.conf does not contain both DVWA log paths."
fi
if [ -r "$OSSEC_LOG" ] && grep -F 'Analyzing file:' "$OSSEC_LOG" | grep -Fq "$ACCESS_LOG" && grep -F 'Analyzing file:' "$OSSEC_LOG" | grep -Fq "$ERROR_LOG"; then
  pass "Wazuh logcollector reports monitoring both DVWA files."
else
  if [ ! -r "$OSSEC_LOG" ]; then
    warn "Cannot read $OSSEC_LOG as this user; run the verifier with sudo to check logcollector monitoring."
  else
    fail "Logcollector monitoring records for both DVWA files were not found in $OSSEC_LOG."
  fi
fi
if [ -r "$ACCESS_LOG" ] && tail -n 1000 "$ACCESS_LOG" | grep -Fq 'sentinelsoc-wazuh-test-'; then
  pass "Recent uniquely marked DVWA test events exist in the host access log."
else
  warn "No uniquely marked DVWA test event was found in the latest 1000 access-log lines."
fi

if (( failures > 0 )); then
  printf '[SUMMARY] FAIL: %s failed, %s warning(s).\n' "$failures" "$warnings"
  exit 1
fi
if (( warnings > 0 )); then
  printf '[SUMMARY] WARN: all accessible required checks passed with %s warning(s).\n' "$warnings"
  exit 0
fi
printf '[SUMMARY] PASS: all required checks passed.\n'
