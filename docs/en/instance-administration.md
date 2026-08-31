---
title: "Administer an OpenIRN instance"
subtitle: "Operations, backup, restore, update, and troubleshooting"
author: "OpenIRN Project"
---

# Purpose

This guide is intended for the technical administrator of an OpenIRN instance. It covers the Linux server, MariaDB, Apache, the API, and the application fleet. Server commands are intended for a `root` session.

Adapt DNS names and versions to your instance. Never copy `/etc/openirn-api*.env` files, PINs, device tokens, enrollment codes, or signing secrets into a ticket or log.

# 1. Architecture overview

```text
Android / Windows / Apple applications
                 |
              HTTPS/443
                 |
              Apache
                 |
       127.0.0.1:8091 only
                 |
        Uvicorn / FastAPI OpenIRN
                 |
     MariaDB on the host or private network
```

Common directories and units:

| Item | Location |
|---|---|
| Active API version | `/opt/openirn-api` |
| Installed versions | `/opt/openirn-releases/vX.Y.Z` |
| Runtime environment | `/etc/openirn-api.env` |
| Migration environment | `/etc/openirn-api-migration.env` |
| Data and referentials | `/var/lib/openirn-api` |
| Backups | `/var/lib/openirn-api/backups` |
| ECS/NDJSON API log | `/var/lib/openirn-api/logs/api-access.ndjson` |
| ECS/NDJSON security log | `/var/lib/openirn-api/logs/security.ndjson` |
| ECS/NDJSON operations log | `/var/lib/openirn-api/logs/operations.ndjson` |
| API | `openirn-api.service` |
| Backup | `openirn-api-backup.service` |
| Schedule | `openirn-api-backup.timer` |

MariaDB is the only server backend. The client stores no persistent business data; it stores only connection metadata, preferences, and the device token in the platform's secure storage.

# 2. Daily checks

## Service status

```bash
systemctl is-active mariadb apache2 openirn-api openirn-api-backup.timer
systemctl is-enabled mariadb apache2 openirn-api openirn-api-backup.timer
```

All units must be `active`; persistent units and the timer must be `enabled`.

## Internal and public health

```bash
curl --fail --silent --show-error http://127.0.0.1:8091/health | jq
curl --fail --silent --show-error https://openirn.example.org/api/health | jq
```

Check these fields:

- `status` equals `ok`;
- `storage` equals `mariadb`;
- `authRequired` equals `true`;
- `authMode` equals `server_session_with_role_policy`.

A `200` health response proves basic availability, not the complete user journey. Regularly supplement it with an acceptance test using a test account and campaign.

## Network listeners

```bash
ss -ltnp | grep -E ':(443|8091|3306)\b'
```

Expected result:

- Apache listens on the intended interfaces on port 443;
- Uvicorn listens only on `127.0.0.1:8091`;
- MariaDB is not exposed publicly.

## Recent errors

```bash
journalctl -u openirn-api --since today --priority warning --no-pager
journalctl -u openirn-api-backup.service --since today --no-pager
tail -n 100 /var/log/apache2/openirn-api-error.log
```

Look for repeated restarts, MariaDB rejections, missing migrations, backup errors, `AH01084`, `AH01097`, `Broken pipe`, `502`, and `503`.

## API traffic and latency

The structured API log produces exactly one event per request and adds the `X-Request-ID` header to responses handled by the middleware. Inspect recent events without modifying the file:

```bash
tail -n 20 /var/lib/openirn-api/logs/api-access.ndjson | jq -c \
	'{timestamp:."@timestamp", route:.url.path, status:.http.response.status_code, duration_ms:(.event.duration / 1000000), trace_id:.trace.id}'
```

Prioritize `5xx` statuses, rising `4xx` rates, and routes whose duration increases. `event.duration` is expressed in nanoseconds. `url.path` contains the FastAPI route template, such as `/campaigns/{campaign_id}`, never the actual identifier. An unrecognized path becomes `/__unmatched__`. The log contains no body, query string, header, client address, or raw business identifier.

After authentication, `device.id` and `organization.id` are HMAC pseudonyms
that can count active clients and tenants without recording their real
identifiers. `openirn.client.platform` is the platform stored for the device by
the server.

## Security events

The security log is separate from the access log. Display recent events without exposing pseudonyms in the output:

```bash
tail -n 50 /var/lib/openirn-api/logs/security.ndjson | jq -c \
	'{timestamp:."@timestamp", action:.event.action, outcome:.event.outcome, severity:.event.severity, reason:.openirn.security.reason, trace_id:.trace.id}'
```

Prioritize `authorization.denied`, `auth.failed`, rate or capacity limits, enrollment code creation or consumption, session or device revocation, and privilege changes. Use `trace.id` to find the corresponding request in `api-access.ndjson` or Kibana. `organization.id`, `user.id`, `device.id`, and fields under `openirn.security` are HMAC pseudonyms, never raw business values. Do not rotate `OPENIRN_API_OBSERVABILITY_HASH_SECRET` during routine maintenance: rotation prevents correlation of the same actor before and after the change.

## Operations events

Inspect API starts and backups without displaying sensitive metadata:

```bash
tail -n 50 /var/lib/openirn-api/logs/operations.ndjson | jq -c \
	'{timestamp:."@timestamp", action:.event.action, outcome:.event.outcome, version:.service.version, automatic:.openirn.operation.automatic}'
```

Expected actions are `service.started`, `backup.created`, and `backup.failed`.
The log contains no backup path, file name, file hash, or signing secret.

## OpenIRN Kibana dashboard

The **OpenIRN — Supervision opérationnelle** dashboard is organized into six sections: **Summary**, **Usage**, **Performance**, **Security**, **Infrastructure**, and **Operations**. It covers availability and backups, pseudonymous usage, p50/p95/p99 latency, Apache, OpenIRN audit events, system resources, MariaDB, systemd, TLS, and the deployed version. Its initial time range is 24 hours, with automatic refresh every minute.

Prioritize the objectives shown in its header:

- synthetic availability at or above 99.9%;
- API p95 latency below 250 ms;
- no HTTP `5xx` response;
- latest successful backup less than 26 hours old and no recent failure;
- CPU below 85%, memory below 90%, and root filesystem below 85%;
- swap below 50%, active systemd services, and Apache workers below 90%;
- TLS certificate valid for more than 30 days;
- no sustained rise in MariaDB connections, running threads, or aborted connections.

Expected denials, such as requests without a session, increase both the `403` and `authorization.denied` counters and do not constitute an incident on their own. Correlate an increase with security reasons, source pseudonyms, and `trace.id`. These pseudonyms are intended only for technical grouping and must not be used to attempt to re-identify a user.

The reproducible dashboard definition is stored in `monitoring/kibana/openirn-api-health-security.json`. Its portable deployment procedure is documented in `monitoring/kibana/README.md`. It requires the ECS `host.name` value of the host to monitor and accepts all Fleet namespaces matching the documented patterns: OpenIRN and Apache logs, Synthetics, System metrics, Apache Status, Linux systemd, and MariaDB. The `PUT` operation fully replaces the dashboard whose identifier is `openirn-api-health-security`; review the JSON diff before every redeployment.

# 3. Weekly checks

## MariaDB

Run the tool with the runtime account without displaying the URL:

```bash
cd /opt/openirn-api
(
	set -a
	. /etc/openirn-api.env
	set +a
	runuser -u www-data -- .venv/bin/python tools/check_runtime_backend.py
)
```

Check table sizes:

```bash
MYSQL_HISTFILE=/dev/null mariadb openirn -e \
	"SELECT table_name, table_rows, ROUND((data_length+index_length)/1024/1024,1) AS mib FROM information_schema.tables WHERE table_schema='openirn' ORDER BY data_length+index_length DESC;"
```

`table_rows` is an InnoDB estimate. Use it to detect abnormal growth, not as an accounting record.

## Available backups

```bash
systemctl list-timers openirn-api-backup.timer --no-pager
find /var/lib/openirn-api/backups -maxdepth 1 -type f \
	-printf '%TY-%Tm-%Td %TH:%TM %s %f\n' | sort
```

Check that a recent backup exists, that all three associated files are present, and that an encrypted copy has left the host.

## TLS certificate

```bash
openssl s_client -connect openirn.example.org:443 \
	-servername openirn.example.org </dev/null 2>/dev/null |
	openssl x509 -noout -subject -issuer -dates
```

Plan renewal before expiry and test the Apache reload.

# 4. Monthly checks

- perform a complete restore into an empty database;
- review active accounts and their roles;
- revoke unnecessary sessions;
- review inactive or unknown devices;
- review security events and repeated rate limits;
- check available releases and dependencies;
- test the update on a test instance or pilot group;
- check that the published PDF documentation matches the version in use.

# 5. Backups

## Scheduled backup

The timer runs a daily backup at the time defined in `openirn-api-backup.timer`. Check its next run:

```bash
systemctl list-timers openirn-api-backup.timer --all --no-pager
```

## Manual backup before a change

```bash
systemctl start openirn-api-backup.service
systemctl is-failed openirn-api-backup.service
journalctl -u openirn-api-backup.service --since '10 minutes ago' --no-pager
```

`systemctl is-failed` must return `inactive`, not `failed`.

Identify recent files:

```bash
find /var/lib/openirn-api/backups -maxdepth 1 -type f \
	-newermt '15 minutes ago' -printf '%f %s bytes\n' | sort
```

The HMAC manifest detects accidental or malicious file modification but does not encrypt the data. Encrypt off-site copies and restrict access to them.

## Retention

`OPENIRN_API_BACKUP_KEEP` sets the number of backups retained locally. Do not reduce retention until external copies have been confirmed. Deleting a backup is irreversible if no other copy exists.

# 6. Restore drill

The official restore procedure targets a **separate, empty database**. By default, the tool rejects the source database and a non-empty target.

## Prepare a test target

Choose a dated name, then open MariaDB without history:

```bash
MYSQL_HISTFILE=/dev/null mariadb
```

Adapt these values:

```sql
CREATE DATABASE openirn_restore_YYYYMMDD
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'openirn_restore'@'localhost'
  IDENTIFIED BY 'PASSWORD_TO_REPLACE';
GRANT ALL PRIVILEGES ON openirn_restore_YYYYMMDD.*
  TO 'openirn_restore'@'localhost';
FLUSH PRIVILEGES;
```

Create a protected temporary file:

```bash
install -o root -g root -m 600 /dev/null /etc/openirn-api-restore.env
vim /etc/openirn-api-restore.env
```

Content:

```text
OPENIRN_RESTORE_MYSQL_URL=mysql+pymysql://openirn_restore:PASSWORD_TO_REPLACE@127.0.0.1:3306/openirn_restore_YYYYMMDD?charset=utf8mb4
```

## Verify and restore

```bash
cd /opt/openirn-api
backup_file="$(find /var/lib/openirn-api/backups -maxdepth 1 \
	-name 'openirn-*.mariadb.sql' -type f -print | sort | tail -n 1)"
test -n "$backup_file"
set -a
. /etc/openirn-api.env
. /etc/openirn-api-restore.env
set +a
.venv/bin/python tools/restore_mariadb.py \
	--backup "$backup_file" \
	--restore \
	--confirm-target openirn_restore_YYYYMMDD \
	--report /var/lib/openirn-api/openirn-restore-verification.json
unset OPENIRN_RESTORE_MYSQL_URL OPENIRN_API_BACKUP_SIGNATURE_SECRET
```

Review the report: migrations, row counts, foreign keys, and orphan categories must all be valid.

## Destroy the test target

The following commands permanently delete the restored database and its account. Run them only after validating the report and the exact target:

```bash
MYSQL_HISTFILE=/dev/null mariadb
```

```sql
DROP DATABASE openirn_restore_YYYYMMDD;
DROP USER 'openirn_restore'@'localhost';
```

Then delete the temporary connection file:

```bash
rm /etc/openirn-api-restore.env
```

# 7. Recovery after loss of the active database

A real restore is a crisis operation:

1. stop the API to prevent further writes;
2. preserve the failed database without modifying it;
3. restore into a new, empty database;
4. validate the restore report;
5. change the runtime URL to the new database;
6. start the API;
7. run internal and public checks;
8. perform a functional acceptance test;
9. delete the former database only after a formal decision and expiry of the rollback period.

Never restore directly over an active or partially populated database.

# 8. Update the API server

## Prepare

1. read the release notes;
2. check client/API compatibility;
3. check available disk space;
4. create and externalize a backup;
5. announce the maintenance window;
6. retain the path of the currently active version.

```bash
df -h /opt /var/lib/openirn-api
readlink -f /opt/openirn-api
systemctl start openirn-api-backup.service
journalctl -u openirn-api-backup.service --since '10 minutes ago' --no-pager
```

## Download the new version

```bash
export OPENIRN_TAG='vX.Y.Z'
update_root="$(mktemp -d)"
curl --fail --location --proto '=https' --tlsv1.2 \
	--output "$update_root/openirn.tar.gz" \
	"https://github.com/archoad/OpenIRN/archive/refs/tags/${OPENIRN_TAG}.tar.gz"
tar --extract --gzip --file "$update_root/openirn.tar.gz" --directory "$update_root"
source_root="$(find "$update_root" -mindepth 1 -maxdepth 1 -type d -name 'OpenIRN-*' -print -quit)"
release_dir="/opt/openirn-releases/${OPENIRN_TAG}"
test -n "$source_root"
test ! -e "$release_dir"
install -d -o root -g root -m 755 "$release_dir"
cp -a "$source_root/server/openirn-api/." "$release_dir/"
python3 -m venv "$release_dir/.venv"
"$release_dir/.venv/bin/python" -m pip install \
	--requirement "$release_dir/requirements-mariadb.txt"
"$release_dir/.venv/bin/python" -m py_compile \
	"$release_dir/app/database_contract.py" \
	"$release_dir/app/version.py" \
	"$release_dir/app/main.py" \
	"$release_dir/tools/"*.py
```

## Migrate and switch

Stopping the service interrupts users and synchronization. Confirm the maintenance window before running this command:

```bash
systemctl stop openirn-api
```

Apply migrations using the new version's code:

```bash
cd "$release_dir"
set -a
. /etc/openirn-api.env
. /etc/openirn-api-migration.env
set +a
.venv/bin/python tools/migrate_mariadb.py
unset OPENIRN_MIGRATION_MYSQL_URL OPENIRN_API_MYSQL_URL
```

The next command replaces the active symbolic link. Returning to the previous code remains possible, but a data migration may not be reversible; a backup is therefore mandatory:

```bash
ln -sfn "$release_dir" /opt/openirn-api
systemctl daemon-reload
systemctl start openirn-api
systemctl is-active openirn-api
```

## Post-update acceptance test

```bash
journalctl -u openirn-api --since '10 minutes ago' --no-pager
curl --fail --silent --show-error http://127.0.0.1:8091/health | jq
curl --fail --silent --show-error https://openirn.example.org/api/health | jq
```

Then check with a pilot device:

- workspace selection;
- opening and locking a session;
- referential access;
- test campaign;
- an authorized write;
- synchronization on a second device;
- summary and export;
- administration according to role.

# 9. Roll back the code

If the new version fails before any irreversible migration, point the link back to the previous version:

```bash
systemctl stop openirn-api
ln -sfn /opt/openirn-releases/vPREVIOUS_VERSION /opt/openirn-api
systemctl start openirn-api
systemctl is-active openirn-api
```

If the schema or data changed, do not blindly start the former code. Restore the backup into a new database, validate it, and then switch the runtime URL according to the recovery plan.

# 10. Update the applications

1. verify release checksums;
2. deploy Android and Windows to a pilot group;
3. update in place without uninstalling;
4. check that enrollment is preserved;
5. test representative roles;
6. monitor the API and security log;
7. expand the deployment wave.

Current releases do not publish signed Apple artifacts.

# 11. Troubleshoot by symptom

## API inactive

```bash
systemctl status openirn-api --no-pager
journalctl -u openirn-api -n 150 --no-pager
```

Then check:

```bash
readlink -f /opt/openirn-api
stat -c '%U %G %a %n' /etc/openirn-api.env
cd /opt/openirn-api
.venv/bin/python -m py_compile app/version.py app/main.py app/database_contract.py
```

Common causes: missing dependency, incorrect MariaDB URL, missing migration, excessive runtime privileges, or missing environment file.

## Internal health OK, public endpoint returns 502

```bash
apache2ctl configtest
systemctl status apache2 --no-pager
tail -n 150 /var/log/apache2/openirn-api-error.log
curl --verbose http://127.0.0.1:8091/health
```

Check `ProxyPass`, the `/api/` path, the certificate, and local network rules.

## 413 response

A `413` response means that the request body exceeds a limit. Defaults are 1 MiB for a normal request, 16 MiB for synchronization, and 5 MiB for an XLSX import, with a maximum decompressed size of 64 MiB.

Do not increase the limit globally without identifying the route and requirement. Also check Apache `LimitRequestBody`.

## 429 response

A `429` response during enrollment indicates an anti-abuse rate limit. Wait for the `Retry-After` period, check the client address reported by the proxy, and look for abnormal repetition in the security log.

## Device unauthorized or 403

Check in this order:

1. selected workspace;
2. device presence in that workspace;
3. active status and absence of revocation;
4. valid user session;
5. role compatible with the action;
6. device and server time.

A device authorized in one workspace is not automatically authorized in another.

## Session expired

Ask the user to return to the home screen and unlock again. If the problem immediately recurs:

```bash
timedatectl status
journalctl -u openirn-api --since '15 minutes ago' --no-pager
```

Check `OPENIRN_SESSION_TTL_MINUTES` and `OPENIRN_SESSION_IDLE_TIMEOUT_MINUTES` without displaying the rest of the environment file.

## Backup failed

```bash
systemctl status openirn-api-backup.service --no-pager
journalctl -u openirn-api-backup.service -n 150 --no-pager
namei -l /var/lib/openirn-api/backups
df -h /var/lib/openirn-api
```

Check the dump binary, `www-data` permissions, disk space, and the presence of a signing secret at least 32 characters long.

## Inconsistent synchronization

- suspend concurrent changes to the affected campaign;
- record the campaign, workspace, devices, and time;
- open **Administration → History / conflicts**;
- compare the current revision with previous revisions;
- restore a revision only after understanding which data will be lost by that choice.

Restoring a campaign creates a new server revision; it is not a full MariaDB restore.

# 12. Security administration in the application

## Users

- promptly disable accounts of people who have left;
- periodically review Administrators and IRN Managers;
- assign a non-trivial temporary PIN only when required;
- confirm that a change is required at the next login;
- use individual named accounts.

## Sessions

Under **Administration → Server sessions**, revoke unknown, old, or incident-related sessions. When an Administrator resets a PIN, the target user's existing sessions are revoked.

## Devices

- check name, platform, workspace, and last activity;
- approve a request only after confirming the requester;
- immediately revoke a lost device;
- remove authorizations that are no longer required;
- keep each device within the minimum required scope.

## Security log

Look for repeated failures, rate limits, code creation, enrollments, revocations, PIN changes, role changes, and user directory replacements. The log must contain no raw business identifier, raw source address, PIN, token, enrollment code, name, or email address. A transactional operation missing from the log may have been rolled back by MariaDB; inspect API errors before treating it as an audit gap.

# 13. Manage workspaces

Each workspace isolates users, campaigns, inventory, and device authorizations. The official referential is global and shared.

When creating a workspace:

1. choose an unambiguous business name;
2. designate an initial IRN Manager;
3. check their contact details and role;
4. explicitly enroll the required devices;
5. create or import the inventory;
6. run a test campaign.

Deleting a workspace is destructive and may delete its associated data. Export anything that must be retained, create a verified backup, and confirm the exact identifier before taking action.

# 14. Official referential

An Administrator uses **Administration → Official aDRI referential** to:

- check the remote version;
- review metadata and the validation report;
- import the current version;
- view history.

Before an update, back up the instance and test the version in an identified test campaign.

# 15. Capacity and cleanup

Monitor:

```bash
df -h
du -sh /var/lib/openirn-api /var/lib/openirn-api/backups /opt/openirn-releases/*
journalctl --disk-usage
```

Do not directly delete MariaDB rows or backup files outside an approved procedure. Retain at least the active API version and the validated rollback version. Check that no process uses a version before removing it.

# 16. Incident record

Collect without secrets:

- date, time, and time zone;
- affected workspace;
- user role;
- application platform and version;
- exact action;
- HTTP status and visible message;
- service status;
- log excerpts limited to the incident window;
- latest known backup;
- recent server or application changes.

Do not collect a PIN, enrollment code, `Authorization` header, `.env` file, private key, or complete dump in a ticket.

# 17. Change checklist

Before:

- [ ] scope and objective approved;
- [ ] version and release notes checked;
- [ ] recent backup created and externalized;
- [ ] rollback defined;
- [ ] pilot group identified;
- [ ] maintenance window announced.

After:

- [ ] services active and enabled;
- [ ] internal and public health checks successful;
- [ ] no restart loop;
- [ ] login and workspace change tested;
- [ ] acceptance read and write tested;
- [ ] multi-device synchronization tested;
- [ ] post-change backup created;
- [ ] result and limitations recorded without secrets.
