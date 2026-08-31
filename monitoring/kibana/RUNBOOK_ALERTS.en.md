# OpenIRN alert runbook

This runbook accompanies the Kibana dashboard
`OpenIRN — Supervision opérationnelle` and the rules defined in
`openirn-alerting-rules.json`.

Rules write state changes to the Kibana log with the `[OpenIRN][ALERTE]` and
`[OpenIRN][RÉTABLI]` prefixes. They do not send email, webhooks, or messages to
external services.

## Common checks

Set the instance-specific values in the current shell:

```bash
export OPENIRN_API_HOST=openirn-api.example.org
export OPENIRN_API_SSH_PORT=22
export OPENIRN_API_SSH_USER=root
export OPENIRN_API_PUBLIC_URL=https://openirn.example.org/api
```

Start by checking time, server state, and the public health endpoint:

```bash
date --iso-8601=seconds
ssh -p "${OPENIRN_API_SSH_PORT}" "${OPENIRN_API_SSH_USER}@${OPENIRN_API_HOST}"
systemctl is-active openirn-api elastic-agent
curl --fail --silent --show-error --max-time 10 \
	http://127.0.0.1:8091/health | jq
exit
curl --fail --silent --show-error --max-time 20 \
	"${OPENIRN_API_PUBLIC_URL}/health" | jq
```

In Kibana, open **Stack Management → Rules**, filter on the `OpenIRN` tag, then
open the rule. Check its latest execution, message, time window, and linked
dashboard before making changes.

Display logged state changes on the Kibana host:

```bash
journalctl -u kibana --since '-30 minutes' --no-pager \
	| grep -F '[OpenIRN]'
```

## Availability and ingestion

| Rule | Condition | First response |
|---|---|---|
| API unavailable | at least 2 failed synthetic checks in 3 min | check public health, Apache, then `openirn-api` |
| Synthetic monitor silent | no measurement for 5 min, confirmed twice | check the agent running the monitor, then Synthetics ingestion |
| API access log silent | no event for 5 min, confirmed twice | check `openirn-api`, the access file, and Elastic Agent on the API host |

If the public endpoint is unavailable while local health works:

```bash
ssh -p "${OPENIRN_API_SSH_PORT}" "${OPENIRN_API_SSH_USER}@${OPENIRN_API_HOST}"
systemctl is-active apache2 openirn-api
journalctl -u apache2 -u openirn-api --since '-15 minutes' --no-pager
ss -lntp | grep -E ':(443|8091)[[:space:]]'
```

For an ingestion loss, do not immediately restart the API. First check that the
files are growing and the agent is active:

```bash
ssh -p "${OPENIRN_API_SSH_PORT}" "${OPENIRN_API_SSH_USER}@${OPENIRN_API_HOST}"
ls -lh /var/lib/openirn-api/logs/
tail -n 5 /var/lib/openirn-api/logs/api-access.ndjson | jq -c .
systemctl is-active elastic-agent
journalctl -u elastic-agent --since '-15 minutes' --no-pager
```

## API errors and latency

| Rule | Condition | First response |
|---|---|---|
| HTTP 5xx burst | at least 3 responses in 5 min | identify correlated routes, traces, and API errors |
| High p95 latency | p95 at least 500 ms over 10 min, at least 5 requests, confirmed twice | compare CPU, memory, MariaDB, and the slow route |

Search recent errors in Discover with `logs-openirn.api-*`, or use ES|QL:

```text
FROM logs-openirn.api-*
| WHERE @timestamp >= NOW() - 15 minutes
| WHERE http.response.status_code >= 500
| KEEP @timestamp, trace.id, http.request.method, url.path,
       http.response.status_code, event.duration
| SORT @timestamp DESC
```

Do not look for request bodies or tokens: they must not be present in the log.
Use `trace.id` to correlate access errors with application logs.

## Security

| Rule | Condition | First response |
|---|---|---|
| Repeated failures | at least 10 authentication failures, rate limits, or denials per pseudonymous source over 5 min | check action, reason, tenant, and recurrence without trying to recover the raw address |
| High severity | at least one severity 7 event over 5 min | immediately handle a rate limit, block, or capacity limit |

Triage query:

```text
FROM logs-openirn.security-*
| WHERE @timestamp >= NOW() - 30 minutes
| KEEP @timestamp, trace.id, event.action, event.outcome, event.severity,
       openirn.security.reason, openirn.security.source_address_hash
| SORT @timestamp DESC
```

Identifiers and addresses are pseudonymized. Do not weaken authentication
protections to silence an alert. For confirmed abuse, preserve evidence, check
anti-abuse settings, and apply blocking at the reverse proxy or network filter
according to the operating procedure.

## Resources and MariaDB

| Rule | Condition | First response |
|---|---|---|
| High CPU | average at least 85% over 10 min, confirmed twice | identify processes and check API latency |
| High memory | average at least 90% over 10 min, confirmed twice | check memory, swap, and top consumers |
| High swap usage | average at least 50% over 10 min, confirmed twice | investigate sustained memory pressure and affected processes |
| Root disk nearly full | usage at least 85% | locate growth without blindly deleting data |
| Aborted MariaDB connections | increase of at least 5 over 10 min | check MariaDB, the API, and connection errors |
| systemd service inactive | a monitored unit is no longer `active`, confirmed twice | inspect the unit and its journal before restarting it |

Non-destructive diagnostics on the API host:

```bash
date --iso-8601=seconds
uptime
free -h
df -h /
ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 15
systemctl is-active mariadb openirn-api
journalctl -u mariadb -u openirn-api --since '-30 minutes' --no-pager
```

Before cleaning disk space, resolve the exact path, measure its size, and
identify its retention policy. Never delete a data stream, MariaDB backup, or
OpenIRN log solely to bring the gauge below the threshold.

## Apache and operations

| Rule | Condition | First response |
|---|---|---|
| Apache proxy errors | at least one proxy error over 5 min | compare local health, Apache logs, and Uvicorn status |
| Apache workers saturated | at least 90% busy workers over 5 min, confirmed twice | measure traffic, slow requests, and Apache capacity |
| Backup stale | no successful backup over 26 h | inspect the timer and backup log before starting another backup |
| Backup failed | at least one failure over 15 min | check disk space, MariaDB, and `openirn-api-backup.service` |
| TLS certificate expiring | 30 days or less remaining | confirm the date and follow the certificate renewal procedure |
| Repeated API restarts | at least 3 API starts over 15 min | investigate crashes, dependency failures, or operator actions |

```bash
systemctl status apache2 openirn-api openirn-api-backup.timer --no-pager
journalctl -u apache2 -u openirn-api -u openirn-api-backup.service \
	--since '-30 minutes' --no-pager
tail -n 20 /var/lib/openirn-api/logs/operations.ndjson | jq -c \
	'{timestamp:."@timestamp", action:.event.action, outcome:.event.outcome, version:.service.version}'
curl --fail --silent --show-error http://127.0.0.1:8092/server-status?auto \
	| grep -E 'BusyWorkers|IdleWorkers'
```

The operations log must not contain backup paths, file names, hashes, or
secrets. For TLS, also check the date externally to verify the certificate chain
actually served to clients.

## Recovery and tuning

A rule automatically recovers when its query no longer returns a result. Check
that normal operation remains stable on the dashboard before closing the
incident.

To adjust a threshold:

1. measure at least seven representative days;
2. edit `openirn-alerting-rules.json` in the repository;
3. validate the ES|QL query over its actual window;
4. review the diff;
5. redeploy with `deploy-alerting-rules.sh`.

Avoid UI-only changes in Kibana: the next deployment restores the versioned
definition.
