# DVWA to Wazuh Log Integration

## Architecture

The local `dvwa` container writes Apache access and error logs inside the container. `Automation/sync_dvwa_logs.sh` reads only new bytes from those files and appends them to `Monitoring/dvwa-logs/` on the Kali host. Persistent byte offsets reduce duplicates between synchronizer restarts and reset safely after log truncation or rotation. A host-installed Wazuh agent can then monitor the two host files with Apache decoding and send events to the Wazuh manager.

```text
DVWA Apache logs -> byte-offset synchronizer -> host log files -> Wazuh agent -> Wazuh manager/indexer/dashboard
```

The synchronizer does not restart, reconfigure, or write into the DVWA container.

## Prerequisites

- The existing `dvwa` container is running and reachable at `http://127.0.0.1:8080`.
- Docker CLI access is available to the user running the synchronizer.
- Wazuh 4.14.6 single-node is already running separately.
- To ingest host files, a Wazuh agent must be installed and enrolled on the Kali host. The repository does not install it.
- `curl`, Bash, and standard Unix utilities are available.

## Start synchronization

From the repository root:

```bash
./Automation/start_dvwa_log_sync.sh
```

Status output is written to `Monitoring/dvwa-logs/sync.log`; the ignored PID file is stored beside it. The direct foreground form is `./Automation/sync_dvwa_logs.sh` and can be stopped with Ctrl+C.

## Generate test traffic

The generator sends harmless GET requests only to the authorized local lab login page. It defaults to 10 requests; an optional positive count may be supplied:

```bash
./Automation/generate_dvwa_requests.sh
./Automation/generate_dvwa_requests.sh 25
```

## Apply the Wazuh agent configuration

First install and enroll the host Wazuh agent using the appropriate administrative process. Review `Monitoring/wazuh-agent/dvwa-localfile.xml`, then run:

```bash
sudo ./Automation/install_wazuh_dvwa_config.sh
```

The installer backs up `/var/ossec/etc/ossec.conf`, prevents duplicate insertion, inserts both `<localfile>` entries before the closing `</ossec_config>`, and runs `/var/ossec/bin/wazuh-logcollector -t`. It restores the backup on validation failure and asks before restarting the agent.

## Verify ingestion

```bash
./Automation/verify_dvwa_wazuh_pipeline.sh
```

The verifier checks the container, HTTP endpoint, container and host logs, host agent installation/service state, configuration paths, and logcollector startup messages. After generating traffic, allow a short interval for synchronization and agent collection, then use the Wazuh dashboard to search the enrolled Kali agent's events.

## Stop synchronization

```bash
./Automation/stop_dvwa_log_sync.sh
```

The stop script verifies the PID belongs to the synchronizer before sending a graceful termination signal.

## Troubleshooting

- **Docker permission denied:** run synchronization as a user authorized to access Docker. Do not loosen the Docker socket permissions globally.
- **Host logs remain empty:** confirm DVWA is running, generate local traffic, and inspect `Monitoring/dvwa-logs/sync.log`.
- **Agent checks fail:** `/var/ossec/etc/ossec.conf` and the `wazuh-agent` service must exist on the Kali host; the Wazuh server containers are not a substitute for a host agent.
- **Configuration validation fails:** the installer restores its timestamped backup. Review validator output and the snippet before retrying.
- **No collector record:** restart the Wazuh agent only after configuration validation and approval, then inspect `/var/ossec/logs/ossec.log` for `Analyzing file:` messages containing both paths.
- **Duplicate lines after unusual rotation:** offsets minimize normal duplicates, but external file replacement or container recreation can make exact identity ambiguous. Review the host log before resetting any `.offset` files manually.

## Events versus alerts

Generating requests creates Apache log **events**. Synchronizing and collecting those events proves transport into the Wazuh pipeline, but it does not guarantee an **alert**. Alerts are emitted only when a Wazuh decoder and rule match an event at an alerting level. Ordinary login-page GET requests may be collected without triggering a rule; alert testing requires a separately reviewed rule or an event pattern known to match existing rules.
