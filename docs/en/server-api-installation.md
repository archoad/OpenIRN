---
title: "Install and initialize the OpenIRN server"
subtitle: "FastAPI, MariaDB, Apache, and first access"
author: "OpenIRN Project"
---

# Purpose and scope

This document describes how to install an OpenIRN API instance behind Apache, with MariaDB as the only server-side database.

This guide assumes that the target server runs GNU/Linux (tested on **Debian 13**) and is administered using the `root` account.

The API server uses:

- Python 3 and a dedicated virtual environment;
- MariaDB with separate migration and runtime accounts;
- Uvicorn bound only to `127.0.0.1:8091`;
- Apache as the HTTPS frontend under the public `/api/` path;
- systemd for the API and daily backups;
- a published OpenIRN version identified by a `vX.Y.Z` Git tag.

# 1. Prepare the required information

Choose the following values before starting:

| Parameter | Documentation example | Purpose |
|---|---|---|
| DNS name | `openirn.example.org` | public API URL |
| OpenIRN tag | `vX.Y.Z` | immutable version to deploy |
| MariaDB database | `openirn` | instance data |
| Administration workspace | `openirn-admin` | source workspace for the solution administrator |
| Release directory | `/opt/openirn-releases` | immutable installations |
| Active link | `/opt/openirn-api` | version currently executed |
| Data directory | `/var/lib/openirn-api` | referentials and backups |

Declare only non-sensitive values:

```bash
export OPENIRN_HOST='openirn.example.org'
export OPENIRN_TAG='vX.Y.Z'
export OPENIRN_ADMIN_TENANT='openirn-admin'
```

Stop if the tag is still the example value:

```bash
test "$OPENIRN_TAG" != 'vX.Y.Z' || {
	echo 'Set OPENIRN_TAG to a published tag' >&2
	exit 1
}
```

# 2. Check the server and DNS

Check the system:

```bash
cat /etc/os-release
uname -m
hostnamectl
```

Expected result: Debian 13, an architecture supported by Python and MariaDB, and a correctly synchronized clock.

Check the time:

```bash
timedatectl status
```

`System clock synchronized` must be `yes`. OpenIRN sessions and temporary codes depend on accurate time.

From an external workstation, the DNS name must resolve to the server:

```bash
dig +short "$OPENIRN_HOST" A
dig +short "$OPENIRN_HOST" AAAA
```

Expose only TCP/443 publicly. MariaDB port 3306 and Uvicorn port 8091 must remain local or filtered.

# 3. Install the prerequisites

```bash
apt update
apt install --yes \
	apache2 \
	ca-certificates \
	curl \
	git \
	jq \
	mariadb-client \
	mariadb-server \
	openssl \
	python3 \
	python3-pip \
	python3-venv \
	tar
```

Check the services and the versions actually installed:

```bash
python3 --version
mariadb --version
apache2ctl -v
systemctl is-active mariadb
systemctl is-active apache2
```

The final two commands must return `active`.

# 4. Download an OpenIRN release

Create the directories:

```bash
install -d -o root -g root -m 755 /opt/openirn-releases
install -d -o www-data -g www-data -m 750 /var/lib/openirn-api
install -d -o www-data -g www-data -m 750 /var/lib/openirn-api/backups
```

Download the source archive for the selected tag:

```bash
install_root="$(mktemp -d)"
curl --fail --location --proto '=https' --tlsv1.2 \
	--output "$install_root/openirn.tar.gz" \
	"https://github.com/archoad/OpenIRN/archive/refs/tags/${OPENIRN_TAG}.tar.gz"
tar --extract --gzip --file "$install_root/openirn.tar.gz" --directory "$install_root"
source_root="$(find "$install_root" -mindepth 1 -maxdepth 1 -type d -name 'OpenIRN-*' -print -quit)"
test -n "$source_root"
test -f "$source_root/server/openirn-api/app/main.py"
```

Deploy only the server component:

```bash
release_dir="/opt/openirn-releases/${OPENIRN_TAG}"
test ! -e "$release_dir"
install -d -o root -g root -m 755 "$release_dir"
cp -a "$source_root/server/openirn-api/." "$release_dir/"
chown -R root:root "$release_dir"
ln -s "$release_dir" /opt/openirn-api
```

Check the link and required files:

```bash
readlink -f /opt/openirn-api
test -f /opt/openirn-api/requirements-mariadb.txt
test -f /opt/openirn-api/sql/schema_mariadb.sql
```

The link must point exactly to `/opt/openirn-releases/$OPENIRN_TAG`.

# 5. Create the Python environment

```bash
python3 -m venv /opt/openirn-api/.venv
/opt/openirn-api/.venv/bin/python -m pip install --upgrade pip
/opt/openirn-api/.venv/bin/python -m pip install \
	--requirement /opt/openirn-api/requirements-mariadb.txt
```

Check imports without starting the API:

```bash
cd /opt/openirn-api
.venv/bin/python -m py_compile app/database_contract.py app/main.py tools/*.py
.venv/bin/python -c 'import fastapi, pymysql, uvicorn; print("Python dependencies OK")'
```

# 6. Create the database and separate privileges

Generate two different random passwords and store them in a secret manager. Hexadecimal values avoid encoding issues in MariaDB URLs:

```bash
openssl rand -hex 32 # RUNTIME_PASSWORD
openssl rand -hex 32 # MIGRATION_PASSWORD
```

Open MariaDB without retaining SQL history:

```bash
MYSQL_HISTFILE=/dev/null mariadb
```

Adapt and execute:

```sql
CREATE DATABASE IF NOT EXISTS openirn
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'openirn_runtime'@'localhost'
  IDENTIFIED BY 'RUNTIME_PASSWORD_TO_REPLACE';
CREATE USER IF NOT EXISTS 'openirn_migration'@'localhost'
  IDENTIFIED BY 'MIGRATION_PASSWORD_TO_REPLACE';

GRANT SELECT, INSERT, UPDATE, DELETE
  ON openirn.* TO 'openirn_runtime'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP, REFERENCES
  ON openirn.* TO 'openirn_migration'@'localhost';
FLUSH PRIVILEGES;

SHOW GRANTS FOR 'openirn_runtime'@'localhost';
SHOW GRANTS FOR 'openirn_migration'@'localhost';
```

The runtime account must not have `CREATE`, `ALTER`, `DROP`, `INDEX`, or `GRANT OPTION`.

# 7. Create the deployment secrets

Generate two separate values:

```bash
openssl rand -hex 32
openssl rand -hex 32
```

The first value signs backup manifests and the second hashes enrollment codes. Rotating the enrollment secret invalidates unconsumed temporary codes.

Create the runtime file, readable only by `root`:

```bash
install -o root -g root -m 600 /dev/null /etc/openirn-api.env
vim /etc/openirn-api.env
```

Minimum content:

```text
OPENIRN_API_MYSQL_URL=mysql+pymysql://openirn_runtime:RUNTIME_PASSWORD_TO_REPLACE@127.0.0.1:3306/openirn?charset=utf8mb4
OPENIRN_API_DATA_DIR=/var/lib/openirn-api
OPENIRN_API_BACKUP_DIR=/var/lib/openirn-api/backups
OPENIRN_API_BACKUP_KEEP=30
OPENIRN_API_BACKUP_AUTO_ENABLED=true
OPENIRN_API_BACKUP_PROTECTIVE_ENABLED=true
OPENIRN_API_BACKUP_SIGNATURE_SECRET=BACKUP_SECRET_TO_REPLACE
OPENIRN_ENROLLMENT_CODE_SECRET=ENROLLMENT_SECRET_TO_REPLACE
OPENIRN_SOLUTION_ADMIN_TENANT_ID=openirn-admin
OPENIRN_TRUSTED_PROXY_CIDRS=127.0.0.1/32,::1/128
OPENIRN_SESSION_TTL_MINUTES=480
OPENIRN_SESSION_IDLE_TIMEOUT_MINUTES=30
```

Create a separate migration file:

```bash
install -o root -g root -m 600 /dev/null /etc/openirn-api-migration.env
vim /etc/openirn-api-migration.env
```

Content:

```text
OPENIRN_MIGRATION_MYSQL_URL=mysql+pymysql://openirn_migration:MIGRATION_PASSWORD_TO_REPLACE@127.0.0.1:3306/openirn?charset=utf8mb4
```

Check permissions without displaying values:

```bash
stat -c '%U %G %a %n' /etc/openirn-api.env /etc/openirn-api-migration.env
```

Expected result: `root root 600` for both files.

# 8. Apply the MariaDB schema

The API does not apply DDL at startup. Temporarily load both files and run the dedicated tool:

```bash
cd /opt/openirn-api
set -a
. /etc/openirn-api.env
. /etc/openirn-api-migration.env
set +a
.venv/bin/python tools/migrate_mariadb.py
unset OPENIRN_MIGRATION_MYSQL_URL OPENIRN_API_MYSQL_URL
```

Expected result: migrations applied, distinct migration and runtime accounts, and runtime privileges limited to `SELECT`, `INSERT`, `UPDATE`, and `DELETE`.

Check the database using the runtime account:

```bash
(
	set -a
	. /etc/openirn-api.env
	set +a
	/opt/openirn-api/.venv/bin/python /opt/openirn-api/tools/check_mariadb_readiness.py
)
```

All listed tables must be readable, and none may be reported missing.

# 9. Install and start the systemd unit

```bash
install -o root -g root -m 644 \
	/opt/openirn-api/systemd/openirn-api.service \
	/etc/systemd/system/openirn-api.service
systemctl daemon-reload
systemctl enable --now openirn-api.service
```

Check the service:

```bash
systemctl is-active openirn-api.service
systemctl is-enabled openirn-api.service
ss -ltnp | grep '127.0.0.1:8091'
curl --fail --silent --show-error http://127.0.0.1:8091/health | jq
```

The JSON response must include:

```json
{
  "status": "ok",
  "storage": "mariadb",
  "authRequired": true,
  "authMode": "server_session_with_role_policy"
}
```

If the check fails:

```bash
journalctl -u openirn-api.service -n 100 --no-pager
```

# 10. Publish the API through Apache and TLS

Enable the required modules:

```bash
a2enmod headers proxy proxy_http ssl
```

First install a valid TLS certificate for `$OPENIRN_HOST` according to your organization's procedure. Adapt the example paths below.

Create the virtual host:

```bash
vim /etc/apache2/sites-available/openirn-api.conf
```

Content:

```apache
<VirtualHost *:443>
    ServerName openirn.example.org

    SSLEngine on
    SSLCertificateFile /etc/ssl/openirn/fullchain.pem
    SSLCertificateKeyFile /etc/ssl/openirn/privkey.pem

    ProxyRequests Off
    ProxyPreserveHost On
    ProxyAddHeaders On
    RequestHeader set X-Forwarded-Proto "https"

    LimitRequestBody 16777216
    ProxyPass        /api/ http://127.0.0.1:8091/ connectiontimeout=5 timeout=120
    ProxyPassReverse /api/ http://127.0.0.1:8091/

    ErrorLog ${APACHE_LOG_DIR}/openirn-api-error.log
    CustomLog ${APACHE_LOG_DIR}/openirn-api-access.log combined
</VirtualHost>
```

Replace the DNS name and certificate paths, then check and enable the site:

```bash
apache2ctl configtest
a2ensite openirn-api.conf
systemctl reload apache2
systemctl is-active apache2
```

Check from a workstation that resolves the DNS name:

```bash
curl --fail --silent --show-error "https://${OPENIRN_HOST}/api/health" | jq
```

Uvicorn must not be reachable externally. Configure `OPENIRN_TRUSTED_PROXY_CIDRS` only with the address of the peer that actually connects to Uvicorn.

# 11. Install automated backups

```bash
install -o root -g root -m 644 \
	/opt/openirn-api/systemd/openirn-api-backup.service \
	/etc/systemd/system/openirn-api-backup.service
install -o root -g root -m 644 \
	/opt/openirn-api/systemd/openirn-api-backup.timer \
	/etc/systemd/system/openirn-api-backup.timer
systemctl daemon-reload
systemctl enable --now openirn-api-backup.timer
systemctl start openirn-api-backup.service
```

Check the backup:

```bash
systemctl list-timers openirn-api-backup.timer --no-pager
journalctl -u openirn-api-backup.service -n 50 --no-pager
find /var/lib/openirn-api/backups -maxdepth 1 -type f -printf '%f %s bytes\n' | sort
```

A valid backup includes the dump, its SHA-256 checksum, and its signed manifest. An off-host copy remains essential.

# 12. Create the first solution administrator

Perform this step once, after running the migrations. The tool refuses to proceed if an active administrator already exists in the target workspace.

```bash
cd /opt/openirn-api
(
	set -a
	. /etc/openirn-api.env
	set +a
	.venv/bin/python tools/create_superuser.py \
		--tenant "$OPENIRN_ADMIN_TENANT" \
		--tenant-name 'OpenIRN Administration' \
		--first-name 'First name' \
		--last-name 'Last name' \
		--email 'admin@example.org'
)
```

Enter a non-trivial temporary PIN twice. It is not displayed and must not be placed on the command line. OpenIRN requires it to be changed at first login.

Check only the count and role, without reading the hash:

```bash
MYSQL_HISTFILE=/dev/null mariadb openirn -e \
	"SELECT tenant_id,email,role,active FROM users WHERE role='administrator';"
```

Restart the API to reconcile the solution administrator with existing workspaces:

```bash
systemctl restart openirn-api
systemctl is-active openirn-api
```

# 13. Bootstrap the first device

List existing workspaces:

```bash
cd /opt/openirn-api
(
	set -a
	. /etc/openirn-api.env
	set +a
	.venv/bin/python tools/create_bootstrap_enrollment.py --list-tenants
)
```

Create a one-time code valid for ten minutes:

```bash
(
	set -a
	. /etc/openirn-api.env
	set +a
	.venv/bin/python tools/create_bootstrap_enrollment.py \
		--tenant "$OPENIRN_ADMIN_TENANT" \
		--label 'First OpenIRN device' \
		--expires 10
)
```

In the application installed on the first workstation:

1. Choose the administration workspace.
2. Open **Authorize this device**.
3. Enter the code displayed by the tool.
4. Unlock OpenIRN using the administrator account and temporary PIN.
5. Immediately choose a new, non-trivial personal PIN.

The code is single-use. Do not retain it after use.

# 14. Load the official referential

With the administrator session open:

1. Open **Administration**.
2. Open **Official aDRI referential**.
3. Select **Check**.
4. Review the version, source, and validation report.
5. Install the detected version if it matches the expected official version.

Return to the home screen and open **aDRI IRN referential**. The pillars and criteria must be displayed.

# 15. Final acceptance checks

Run these checks:

```bash
systemctl is-active mariadb apache2 openirn-api openirn-api-backup.timer
curl --fail --silent --show-error http://127.0.0.1:8091/health | jq
curl --fail --silent --show-error "https://${OPENIRN_HOST}/api/health" | jq
journalctl -u openirn-api --since '15 minutes ago' --no-pager
journalctl -u openirn-api-backup.service -n 50 --no-pager
```

Commissioning is complete when:

- MariaDB, Apache, the API, and the timer are active;
- the API listens only on `127.0.0.1:8091`;
- both internal and HTTPS health checks return `200`;
- the first device is enrolled in the correct workspace;
- the administrator has replaced the temporary PIN;
- the official referential is installed and readable;
- a signed backup has been produced and copied off-host.

# Quick installation troubleshooting

| Symptom | Check | Common cause |
|---|---|---|
| API does not start | `journalctl -u openirn-api -n 100` | missing migration or excessive runtime privileges |
| Apache returns `502` | `curl http://127.0.0.1:8091/health` | Uvicorn stopped or incorrect `ProxyPass` |
| Application returns `403` | check workspace, device, and session | device not enrolled in this workspace or expired session |
| Enrollment code rejected | check time and code lifetime | expired or consumed code, or different enrollment secret |
| Backup rejected | inspect backup unit journal | signing secret too short or directory permissions incorrect |
| Referential missing | check Official aDRI referential screen | import not performed or outbound GitLab access unavailable |
