#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CONTAINER="${WAZUH_MANAGER_CONTAINER:-single-node-wazuh.manager-1}"
BASE_SOURCE="$REPO_ROOT/Monitoring/wazuh-manager/rules/dvwa_auth_failure.xml"
BASE_TARGET="/var/ossec/etc/rules/dvwa_auth_failure.xml"
SIGMA_SOURCE="$REPO_ROOT/Monitoring/rules/sigma/wazuh/dvwa_sigma_auth_correlation.xml"
SIGMA_TARGET="/var/ossec/etc/rules/dvwa_sigma_auth_correlation.xml"

fail() { printf '[sigma-install] ERROR: %s\n' "$*" >&2; exit 1; }
status() { printf '[sigma-install] %s\n' "$*"; }

command -v docker >/dev/null 2>&1 || fail "docker is not available."
[ -r "$BASE_SOURCE" ] || fail "DVWA base rule is missing: $BASE_SOURCE"
[ -r "$SIGMA_SOURCE" ] || fail "Adapted Wazuh rule is missing: $SIGMA_SOURCE"
docker inspect "$CONTAINER" >/dev/null 2>&1 || fail "Manager container is unavailable: $CONTAINER"

docker cp "$BASE_SOURCE" "$CONTAINER:$BASE_TARGET"
docker cp "$SIGMA_SOURCE" "$CONTAINER:$SIGMA_TARGET"
docker exec "$CONTAINER" chown root:wazuh "$BASE_TARGET" "$SIGMA_TARGET"
docker exec "$CONTAINER" chmod 0640 "$BASE_TARGET" "$SIGMA_TARGET"

if ! docker exec "$CONTAINER" /var/ossec/bin/wazuh-analysisd -t; then
  fail "Wazuh rejected the adapted Sigma rule; manager was not restarted."
fi

docker exec "$CONTAINER" /var/ossec/bin/wazuh-control restart
status "Installed Sigma-adapted rule 100111 and restarted Wazuh manager processes."
