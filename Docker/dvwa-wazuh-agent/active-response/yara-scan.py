#!/usr/bin/env python3
"""Safely scan a Wazuh FIM event from the controlled SentinelSOC drop directory."""

import json
import os
from pathlib import Path
import subprocess
import sys


MONITORED_ROOT = Path("/sentinelsoc/yara-drop")
YARA = "/usr/local/bin/yara"
RULES = "/etc/yara-rules/sentinelsoc-test.yar"
LOG = Path("/var/ossec/logs/active-responses.log")
MAX_FILE_SIZE = 10 * 1024 * 1024


def log(message: str) -> None:
    with LOG.open("a", encoding="utf-8") as stream:
        stream.write(f"wazuh-yara: {message}\n")


def main() -> int:
    try:
        message = json.loads(sys.stdin.readline())
        if message.get("command") != "add":
            return 0

        raw_path = message["parameters"]["alert"]["syscheck"]["path"]
        candidate = Path(raw_path)
        if candidate.is_symlink():
            raise ValueError("symbolic links are not scanned")

        root = MONITORED_ROOT.resolve(strict=True)
        target = candidate.resolve(strict=True)
        if os.path.commonpath((str(root), str(target))) != str(root):
            raise ValueError("event path is outside the monitored directory")

        stat_result = target.stat()
        if not target.is_file():
            raise ValueError("event path is not a regular file")
        if stat_result.st_size > MAX_FILE_SIZE:
            raise ValueError("file exceeds the 10 MiB scan limit")

        result = subprocess.run(
            [YARA, "--no-warnings", RULES, str(target)],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        if result.returncode not in (0, 1):
            detail = result.stderr.strip().replace("\n", " ")[:300]
            raise RuntimeError(f"YARA exited with {result.returncode}: {detail}")

        for output_line in result.stdout.splitlines():
            fields = output_line.split(maxsplit=1)
            if len(fields) == 2:
                rule_name, matched_file = fields
                log(f"INFO - Scan result: {rule_name} {matched_file}")
        return 0
    except (KeyError, TypeError, ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        log(f"ERROR - Scan rejected: {str(error).replace(chr(10), ' ')[:300]}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
