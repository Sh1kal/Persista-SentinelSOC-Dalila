# Curated Sigma Support for Wazuh

Sigma YAML is vendor-neutral detection source content and cannot be loaded directly by Wazuh. This lab keeps the official upstream repository for review, copies only approved YAML into a small selection, and implements compatible logic as native Wazuh XML.

## Directory layout

- `Monitoring/rules/sigma/source/` is an ignored shallow clone of `https://github.com/SigmaHQ/sigma.git`.
- `Monitoring/rules/sigma/selected/` contains exact, reviewed copies of approved upstream YAML rules.
- `Monitoring/rules/sigma/wazuh/` contains the native Wazuh adaptations that can actually run in this lab.

Clone the source repository for the first time:

```bash
git clone --depth 1 https://github.com/SigmaHQ/sigma.git Monitoring/rules/sigma/source
```

Safely clone or update it using the daily-update helper:

```bash
./Automation/update_sigma_source.sh
```

The helper accepts only the official SigmaHQ origin, refuses a dirty source tree,
creates a dated Git bundle in `Monitoring/rules/sigma/backups/`, performs only a
fast-forward update, and parses every upstream YAML document with PyYAML. It does
not copy, convert, install, or deploy rules. Schedule that command daily with the
host scheduler if desired; overlapping runs are rejected by a lock directory.

Example user crontab entry (the absolute path makes the execution scope explicit):

```cron
17 3 * * * /home/kali/Persista-SentinelSOC/Automation/update_sigma_source.sh >>/tmp/sentinelsoc-sigma-update.log 2>&1
```

## Initial approved rule

The exact selected source is SigmaHQ rule `70ed1d26-0050-4b38-a599-92c53d57d45a`, **Bitbucket User Login Failure**, from:

`rules/application/bitbucket/audit/bitbucket_audit_user_login_failure_detected.yml`

The reviewed copy is stored at
`Monitoring/rules/sigma/selected/bitbucket_audit_user_login_failure_detected.yml`.
Before approving an upstream refresh, compare it with the source copy using
`cmp` or `git diff --no-index`; the updater never changes the selected copy.

The upstream rule detects authentication failures and recommends correlation. Its Bitbucket product fields are not sent to Wazuh and are therefore not used directly. The compatible behavior is mapped to fields already normalized by existing Wazuh rule `100110`:

| Detection concept | Sigma source | DVWA/Wazuh adaptation |
| --- | --- | --- |
| Authentication category | `auditType.category: Authentication` | `event_type: dvwa_auth_failure` through rule `100110` |
| Failed result | `auditType.action: User login failed` | `result: failure` through rule `100110` |
| Correlation key | Upstream recommendation: user | `same_source_ip`, available in DVWA JSON |
| Threshold | Recommended correlation | 5 matches in 60 seconds |

The adapted rule is `Monitoring/rules/sigma/wazuh/dvwa_sigma_auth_correlation.xml`, Wazuh rule ID `100111`. It correlates five matches of base rule `100110` from one source IP within 60 seconds. The established ID, level, threshold, and same-source-IP behavior are retained so existing DVWA alert history and dashboard searches remain compatible; the rule now also records Sigma provenance and the `sigma` group.

## Install and test

Install and validate the single approved Wazuh adaptation:

```bash
./Automation/install_sigma_wazuh_rule.sh
```

Generate exactly five harmless failed login attempts against the local DVWA lab:

```bash
./Automation/test_sigma_dvwa_logins.sh 5
```

Confirm rule `100111` in the manager alert file:

```bash
docker exec single-node-wazuh.manager-1 \
  grep '"id":"100111"' /var/ossec/logs/alerts/alerts.json
```

Confirm the same event is searchable in the indexer (credentials are those in
the lab's Wazuh deployment configuration):

```text
GET wazuh-alerts-*/_search
{
  "query": { "term": { "rule.id": "100111" } }
}
```

In the Wazuh Dashboard, select the `wazuh-alerts-*` index pattern and use either query:

```text
rule.id:100111 AND rule.groups:sigma
rule.groups:sigma AND agent.name:dvwa-sentinelsoc
```

Open **Threat Hunting** (or **Discover**), set a time range that includes the
test, paste one of those queries into the search bar, and verify that the result
shows rule ID `100111`, rule level `12`, and the expected `data.srcip`.

## Validation record

On 2026-07-22 the updater validated 4,241 YAML files at SigmaHQ commit
`2dbc894640dda893f3bfec6326c241df7b4b03b3`. Wazuh 4.14.6 accepted the XML,
five real failed login requests produced rule `100111` in
`/var/ossec/logs/alerts/alerts.json`, and the same event was returned from index
`wazuh-alerts-4.x-2026.07.22`. The Dashboard service was running and serving its
authenticated interface. Regression log tests continued to match DVWA base rule
`100110` and YARA rule `100123`.

This selection does not enable bulk conversion or import. Additional Sigma rules must first be checked against log sources and fields actually collected by the lab, copied into `selected`, and explicitly adapted and tested in `wazuh`.
