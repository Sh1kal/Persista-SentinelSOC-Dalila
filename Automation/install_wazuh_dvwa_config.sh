#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SNIPPET="$REPO_ROOT/Monitoring/wazuh-agent/dvwa-localfile.xml"
CONFIG="/var/ossec/etc/ossec.conf"
VALIDATOR="/var/ossec/bin/wazuh-logcollector"
ACCESS_PATH="$REPO_ROOT/Monitoring/dvwa-logs/access.log"
ERROR_PATH="$REPO_ROOT/Monitoring/dvwa-logs/error.log"

fail() { printf '[wazuh-dvwa-config] ERROR: %s\n' "$*" >&2; exit 1; }
status() { printf '[wazuh-dvwa-config] %s\n' "$*"; }

(( EUID == 0 )) || fail "Run this script with sudo: sudo $0"
[ -f "$CONFIG" ] || fail "$CONFIG does not exist; install/enroll the Wazuh agent first."
[ -r "$SNIPPET" ] || fail "Configuration snippet is missing: $SNIPPET"
[ -x "$VALIDATOR" ] || fail "Validator is missing or not executable: $VALIDATOR"

if grep -Fq "$ACCESS_PATH" "$CONFIG" && grep -Fq "$ERROR_PATH" "$CONFIG"; then
  status "Both DVWA log paths are already configured; no changes made."
  exit 0
fi
if grep -Fq "$ACCESS_PATH" "$CONFIG" || grep -Fq "$ERROR_PATH" "$CONFIG"; then
  fail "Only one DVWA log path is already present; resolve the partial configuration manually."
fi

timestamp="$(date +'%Y%m%d-%H%M%S')"
backup="$CONFIG.dvwa-backup-$timestamp"
temp="$(mktemp /var/ossec/etc/ossec.conf.dvwa.XXXXXX)" || fail "Could not create a temporary config file."
cleanup() { rm -f "$temp"; }
trap cleanup EXIT

cp -a "$CONFIG" "$backup" || fail "Could not create backup $backup"
status "Backup created: $backup"

closing_count="$(grep -c '^[[:space:]]*</ossec_config>[[:space:]]*$' "$CONFIG")"
if [ "$closing_count" -ne 1 ]; then
  cp -a "$backup" "$CONFIG"
  fail "Expected exactly one final </ossec_config> tag; original configuration restored."
fi

awk -v snippet="$SNIPPET" '
  /^[[:space:]]*<\/ossec_config>[[:space:]]*$/ {
    while ((getline line < snippet) > 0) print line
    close(snippet)
  }
  { print }
' "$CONFIG" > "$temp" || { cp -a "$backup" "$CONFIG"; fail "Could not build the updated configuration."; }
chown --reference="$CONFIG" "$temp"
chmod --reference="$CONFIG" "$temp"
mv "$temp" "$CONFIG" || { cp -a "$backup" "$CONFIG"; fail "Could not install the updated configuration."; }

if ! "$VALIDATOR" -t; then
  cp -a "$backup" "$CONFIG"
  fail "Validation failed; restored $backup."
fi
status "Configuration installed and validated successfully."

printf '[wazuh-dvwa-config] Restart wazuh-agent now? [y/N] '
read -r answer
case "$answer" in
  y|Y|yes|YES)
    if systemctl restart wazuh-agent; then
      status "wazuh-agent restarted successfully."
    else
      fail "Configuration is valid, but wazuh-agent failed to restart."
    fi
    ;;
  *) status "Restart skipped. Apply later with: sudo systemctl restart wazuh-agent" ;;
esac
