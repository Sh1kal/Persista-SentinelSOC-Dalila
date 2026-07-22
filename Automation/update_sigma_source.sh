#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SIGMA_DIR="$REPO_ROOT/Monitoring/rules/sigma/source"
BACKUP_DIR="$REPO_ROOT/Monitoring/rules/sigma/backups"
LOCK_DIR="$REPO_ROOT/Monitoring/rules/sigma/.update-lock"
UPSTREAM_URL="https://github.com/SigmaHQ/sigma.git"

fail() { printf '[sigma-update] ERROR: %s\n' "$*" >&2; exit 1; }
status() { printf '[sigma-update] %s\n' "$*"; }
cleanup() { rmdir "$LOCK_DIR" 2>/dev/null || true; }

command -v git >/dev/null 2>&1 || fail "git is not available."
command -v python3 >/dev/null 2>&1 || fail "python3 is not available."
python3 -c 'import yaml' 2>/dev/null || fail "PyYAML is required (python3 -m pip install PyYAML)."
mkdir -p "$(dirname -- "$LOCK_DIR")" "$BACKUP_DIR"
mkdir "$LOCK_DIR" 2>/dev/null || fail "another Sigma update is already running."
trap cleanup EXIT

if [ ! -d "$SIGMA_DIR/.git" ]; then
  [ ! -e "$SIGMA_DIR" ] || fail "$SIGMA_DIR exists but is not a Git repository."
  status "Cloning the official SigmaHQ repository."
  git clone --depth 1 "$UPSTREAM_URL" "$SIGMA_DIR"
else
  origin_url="$(git -C "$SIGMA_DIR" remote get-url origin)"
  [ "$origin_url" = "$UPSTREAM_URL" ] || fail "unexpected origin: $origin_url"
  [ -z "$(git -C "$SIGMA_DIR" status --porcelain)" ] || fail "source clone has local changes; refusing to overwrite them."

  old_head="$(git -C "$SIGMA_DIR" rev-parse HEAD)"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  backup="$BACKUP_DIR/sigma-source-${timestamp}-${old_head:0:12}.bundle"
  git -C "$SIGMA_DIR" bundle create "$backup" HEAD
  status "Saved pre-update backup: $backup"

  git -C "$SIGMA_DIR" fetch --depth 1 origin
  upstream_head="$(git -C "$SIGMA_DIR" rev-parse origin/HEAD)"
  if [ "$old_head" != "$upstream_head" ]; then
    git -C "$SIGMA_DIR" merge --ff-only "$upstream_head"
  fi
fi

status "Validating all upstream YAML files."
python3 - "$SIGMA_DIR" <<'PY'
import pathlib
import sys
import yaml

root = pathlib.Path(sys.argv[1])
files = sorted((*root.rglob("*.yml"), *root.rglob("*.yaml")))
if not files:
    raise SystemExit("no YAML files found")
for path in files:
    try:
        with path.open("r", encoding="utf-8") as stream:
            list(yaml.safe_load_all(stream))
    except Exception as exc:
        print(f"invalid YAML: {path}: {exc}", file=sys.stderr)
        raise SystemExit(1)
print(f"validated {len(files)} YAML files")
PY

status "Sigma source is current at $(git -C "$SIGMA_DIR" rev-parse HEAD)."
status "No selected rule or Wazuh rule was deployed; approval and manual adaptation remain required."
