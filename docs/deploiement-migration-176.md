# Déploiement opérateur de la migration 176

Ce runbook prépare le déploiement de `176 canonical_asset_evaluator_assignments`
sur `srv`. Toutes les commandes de cette page sont à exécuter en `root` sur le
serveur, dans une même session Bash. Elles n'affichent pas les secrets des
fichiers d'environnement.

Le répertoire préparé par Codex est :

```text
/home/codex/deployments/openirn-m176-20260928T094555Z
```

La migration garantit une seule affectation par couple `(tenant_id, asset_id)`.
Elle ne reprend l'ancien évaluateur que lorsqu'un actif n'a qu'un évaluateur
dans chaque campagne concernée et que toutes ces campagnes désignent le même
évaluateur actif du même tenant. Les situations ambiguës restent non affectées
et doivent être arbitrées ensuite par un Pilote IRN.

## 1. Ouvrir une session contrôlée

La procédure s'arrête à la première erreur. Ne pas désactiver cette protection.

```bash
bash
set -Eeuo pipefail
umask 077

export STAGE='/home/codex/deployments/openirn-m176-20260928T094555Z'
export STAGED_API="$STAGE/server/openirn-api"
export APP_DIR='/opt/openirn-api'
export DRILL_DB='openirn_restore_m176_test'
export DRILL_ENV='/run/openirn-m176-drill.env'

test "$(hostname -s)" = 'srv'
test "$(systemctl show openirn-api -p WorkingDirectory --value)" = "$APP_DIR"
test -d "$APP_DIR"
test ! -L "$APP_DIR"
test -d "$STAGED_API"
test -f "$STAGE/MANIFEST.sha256"
test -f "$STAGE/BASELINE.sha256"
test "$(stat -c '%U:%G:%a' /etc/openirn-api.env)" = 'root:root:600'
test "$(stat -c '%U:%G:%a' /etc/openirn-api-migration.env)" = 'root:root:600'

cd "$STAGE"
sha256sum --check MANIFEST.sha256
cd "$APP_DIR"
sha256sum --check "$STAGE/BASELINE.sha256"
systemctl is-active --quiet mariadb
systemctl is-active --quiet openirn-api
mariadb --version
curl --fail --silent --show-error --max-time 10 \
	http://127.0.0.1:8091/health | jq .
```

Résultat attendu : les trois empreintes sont valides, MariaDB et l'API sont
actifs et la santé indique `storage: mariadb`.

Contrôler la syntaxe du code préparé avec l'environnement Python déjà installé :

```bash
"$APP_DIR/.venv/bin/python" -m py_compile \
	"$STAGED_API/app/database_contract.py" \
	"$STAGED_API/app/main.py" \
	"$STAGED_API/tools/migrate_mariadb.py"
```

## 2. Confirmer l'état initial de la base

Le nom réel de la base est dérivé de la configuration, sans afficher l'URL ni
le mot de passe.

```bash
set -a
. /etc/openirn-api.env
set +a

export DB_NAME
DB_NAME="$("$APP_DIR/.venv/bin/python" -c '
import os, sys
sys.path.insert(0, "/opt/openirn-api/tools")
from backup_mariadb import parse_mysql_url
print(parse_mysql_url(os.environ["OPENIRN_API_MYSQL_URL"])["database"])
')"

case "$DB_NAME" in
	''|*[!A-Za-z0-9_]*) echo 'Nom de base refusé' >&2; exit 1 ;;
esac

MYSQL_HISTFILE=/dev/null mariadb --database="$DB_NAME" --table --execute "
SELECT VERSION() AS mariadb_version;
SELECT version, name
FROM schema_migrations
WHERE version >= 173
ORDER BY version;
SELECT
  (SELECT COUNT(*) FROM campaign_states) AS campaigns,
  (SELECT COUNT(*) FROM information_assets) AS assets,
  (SELECT COUNT(*) FROM users WHERE active = 1 AND role = 'evaluator') AS active_evaluators;
"

test "$(MYSQL_HISTFILE=/dev/null mariadb --database="$DB_NAME" --batch --skip-column-names \
	--execute="SELECT COUNT(*) FROM schema_migrations WHERE version=175 AND name='global_administrator_role'")" = '1'
test "$(MYSQL_HISTFILE=/dev/null mariadb --database="$DB_NAME" --batch --skip-column-names \
	--execute="SELECT COUNT(*) FROM schema_migrations WHERE version=176")" = '0'
```

Ces deux derniers contrôles bloquent si la base n'est pas exactement au point
de départ attendu. Si `176` existe déjà, ne pas poursuivre : il faut auditer
l'état au lieu de rejouer aveuglément le déploiement.

## 3. Créer et vérifier une sauvegarde signée

Cette première sauvegarde est créée avec les outils actuellement déployés,
donc avec le contrat de base antérieur à la migration 176.

```bash
export BACKUP_DIR="${OPENIRN_API_BACKUP_DIR:-/var/lib/openirn-api/backups}"
export BACKUP_MARKER='/run/openirn-m176-backup-started'
touch "$BACKUP_MARKER"

cd "$APP_DIR"
"$APP_DIR/.venv/bin/python" tools/backup_mariadb.py \
	--manual \
	--reason pre-migration-176-drill \
	--verbose

mapfile -d '' -t CREATED_BACKUPS < <(
	find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.mariadb.sql' \
		-newer "$BACKUP_MARKER" -print0
)
test "${#CREATED_BACKUPS[@]}" = '1'
export BACKUP_PATH="${CREATED_BACKUPS[0]}"

"$APP_DIR/.venv/bin/python" tools/restore_mariadb.py \
	--backup "$BACKUP_PATH" \
	--report /root/openirn-m176-backup-verification.json
chmod 600 /root/openirn-m176-backup-verification.json
```

Le dernier rapport doit indiquer une signature valide. Le dump, son fichier
`.sha256` et son manifeste `.json` doivent rester ensemble.

## 4. Restaurer dans une base isolée

Cette étape crée deux comptes éphémères limités à la base de drill. Elle refuse
d'écraser une base ou des comptes préexistants.

```bash
test "$(MYSQL_HISTFILE=/dev/null mariadb --batch --skip-column-names \
	--execute="SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$DRILL_DB'")" = '0'
test "$(MYSQL_HISTFILE=/dev/null mariadb --batch --skip-column-names \
	--execute="SELECT COUNT(*) FROM mysql.user WHERE User='openirn_m176_migration' AND Host='127.0.0.1'")" = '0'
test "$(MYSQL_HISTFILE=/dev/null mariadb --batch --skip-column-names \
	--execute="SELECT COUNT(*) FROM mysql.user WHERE User='openirn_m176_runtime' AND Host='127.0.0.1'")" = '0'

DRILL_MIGRATION_PASSWORD="$(openssl rand -hex 32)"
DRILL_RUNTIME_PASSWORD="$(openssl rand -hex 32)"

MYSQL_HISTFILE=/dev/null mariadb <<SQL
CREATE DATABASE \`$DRILL_DB\`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'openirn_m176_migration'@'127.0.0.1'
  IDENTIFIED BY '$DRILL_MIGRATION_PASSWORD';
CREATE USER 'openirn_m176_runtime'@'127.0.0.1'
  IDENTIFIED BY '$DRILL_RUNTIME_PASSWORD';
GRANT ALL PRIVILEGES ON \`$DRILL_DB\`.*
  TO 'openirn_m176_migration'@'127.0.0.1';
GRANT SELECT, INSERT, UPDATE, DELETE ON \`$DRILL_DB\`.*
  TO 'openirn_m176_runtime'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

install -o root -g root -m 600 /dev/null "$DRILL_ENV"
printf '%s\n' \
	"OPENIRN_M176_MIGRATION_URL=mysql+pymysql://openirn_m176_migration:${DRILL_MIGRATION_PASSWORD}@127.0.0.1:3306/${DRILL_DB}?charset=utf8mb4" \
	"OPENIRN_M176_RUNTIME_URL=mysql+pymysql://openirn_m176_runtime:${DRILL_RUNTIME_PASSWORD}@127.0.0.1:3306/${DRILL_DB}?charset=utf8mb4" \
	> "$DRILL_ENV"
unset DRILL_MIGRATION_PASSWORD DRILL_RUNTIME_PASSWORD

set -a
. "$DRILL_ENV"
set +a
export OPENIRN_RESTORE_MYSQL_URL="$OPENIRN_M176_MIGRATION_URL"

"$APP_DIR/.venv/bin/python" "$APP_DIR/tools/restore_mariadb.py" \
	--backup "$BACKUP_PATH" \
	--restore \
	--confirm-target "$DRILL_DB" \
	--report /root/openirn-m176-restore-drill.json
chmod 600 /root/openirn-m176-restore-drill.json
unset OPENIRN_RESTORE_MYSQL_URL
```

Ne jamais remplacer le nom de la base par la base de production et ne pas
ajouter `--allow-non-drill-target` à ce drill.

## 5. Appliquer deux fois la migration sur le drill

L'outil exécuté est celui du répertoire préparé ; l'environnement Python reste
celui de production, car aucune dépendance n'a changé.

```bash
export OPENIRN_MIGRATION_MYSQL_URL="$OPENIRN_M176_MIGRATION_URL"
export OPENIRN_API_MYSQL_URL="$OPENIRN_M176_RUNTIME_URL"

"$APP_DIR/.venv/bin/python" "$STAGED_API/tools/migrate_mariadb.py"
"$APP_DIR/.venv/bin/python" "$STAGED_API/tools/migrate_mariadb.py"
```

Contrôler l'idempotence et les invariants :

```bash
test "$(MYSQL_HISTFILE=/dev/null mariadb --database="$DRILL_DB" --batch --skip-column-names \
	--execute="SELECT COUNT(*) FROM schema_migrations WHERE version=176 AND name='canonical_asset_evaluator_assignments'")" = '1'

test "$(MYSQL_HISTFILE=/dev/null mariadb --database="$DRILL_DB" --batch --skip-column-names \
	--execute="SELECT GROUP_CONCAT(column_name ORDER BY seq_in_index) FROM information_schema.statistics WHERE table_schema='$DRILL_DB' AND table_name='asset_evaluator_assignments' AND index_name='PRIMARY'")" = 'tenant_id,asset_id'

test "$(MYSQL_HISTFILE=/dev/null mariadb --database="$DRILL_DB" --batch --skip-column-names \
	--execute="SELECT COUNT(*) FROM asset_evaluator_assignments a LEFT JOIN information_assets i ON i.tenant_id=a.tenant_id AND i.asset_id=a.asset_id WHERE i.asset_id IS NULL")" = '0'

test "$(MYSQL_HISTFILE=/dev/null mariadb --database="$DRILL_DB" --batch --skip-column-names \
	--execute="SELECT COUNT(*) FROM asset_evaluator_assignments a LEFT JOIN users u ON u.tenant_id=a.tenant_id AND u.user_id=a.user_id WHERE u.user_id IS NULL OR u.active<>1 OR u.role<>'evaluator'")" = '0'

MYSQL_HISTFILE=/dev/null mariadb --database="$DRILL_DB" --table --execute "
SELECT COUNT(*) AS canonical_assignments FROM asset_evaluator_assignments;
SELECT COUNT(*) AS assets_without_assignment
FROM information_assets i
LEFT JOIN asset_evaluator_assignments a
  ON a.tenant_id=i.tenant_id AND a.asset_id=i.asset_id
WHERE a.asset_id IS NULL;
"

touch /run/openirn-m176-drill.ok
unset OPENIRN_MIGRATION_MYSQL_URL OPENIRN_API_MYSQL_URL
```

Un nombre non nul d'actifs sans affectation n'est pas une erreur : il comprend
les actifs sans ancien évaluateur et les cas ambigus volontairement ignorés.

## 6. Fenêtre de maintenance et sauvegarde finale

À partir d'ici, l'API devient indisponible quelques instants. L'arrêt empêche
une modification concurrente des campagnes pendant le backfill canonique.

```bash
test -f /run/openirn-m176-drill.ok
export MAINTENANCE_START
MAINTENANCE_START="$(date --iso-8601=seconds)"

systemctl stop openirn-api
test "$(systemctl is-active openirn-api || true)" = 'inactive'

set -a
. /etc/openirn-api.env
set +a

FINAL_BACKUP_MARKER='/run/openirn-m176-final-backup-started'
touch "$FINAL_BACKUP_MARKER"
cd "$APP_DIR"
"$APP_DIR/.venv/bin/python" tools/backup_mariadb.py \
	--manual \
	--reason pre-migration-176-production \
	--verbose

mapfile -d '' -t FINAL_BACKUPS < <(
	find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.mariadb.sql' \
		-newer "$FINAL_BACKUP_MARKER" -print0
)
test "${#FINAL_BACKUPS[@]}" = '1'
export FINAL_BACKUP_PATH="${FINAL_BACKUPS[0]}"

"$APP_DIR/.venv/bin/python" tools/restore_mariadb.py \
	--backup "$FINAL_BACKUP_PATH" \
	--report /root/openirn-m176-final-backup-verification.json
chmod 600 /root/openirn-m176-final-backup-verification.json
```

Si une commande de cette section échoue, redémarrer immédiatement l'ancien
service avec `systemctl start openirn-api` et ne pas poursuivre.

## 7. Migrer la base de production

```bash
set -a
. /etc/openirn-api.env
. /etc/openirn-api-migration.env
set +a

"$APP_DIR/.venv/bin/python" "$STAGED_API/tools/migrate_mariadb.py"
"$APP_DIR/.venv/bin/python" "$STAGED_API/tools/migrate_mariadb.py"

test "$(MYSQL_HISTFILE=/dev/null mariadb --database="$DB_NAME" --batch --skip-column-names \
	--execute="SELECT COUNT(*) FROM schema_migrations WHERE version=176 AND name='canonical_asset_evaluator_assignments'")" = '1'

test "$(MYSQL_HISTFILE=/dev/null mariadb --database="$DB_NAME" --batch --skip-column-names \
	--execute="SELECT GROUP_CONCAT(column_name ORDER BY seq_in_index) FROM information_schema.statistics WHERE table_schema='$DB_NAME' AND table_name='asset_evaluator_assignments' AND index_name='PRIMARY'")" = 'tenant_id,asset_id'

test "$(MYSQL_HISTFILE=/dev/null mariadb --database="$DB_NAME" --batch --skip-column-names \
	--execute="SELECT COUNT(*) FROM asset_evaluator_assignments a LEFT JOIN information_assets i ON i.tenant_id=a.tenant_id AND i.asset_id=a.asset_id WHERE i.asset_id IS NULL")" = '0'

test "$(MYSQL_HISTFILE=/dev/null mariadb --database="$DB_NAME" --batch --skip-column-names \
	--execute="SELECT COUNT(*) FROM asset_evaluator_assignments a LEFT JOIN users u ON u.tenant_id=a.tenant_id AND u.user_id=a.user_id WHERE u.user_id IS NULL OR u.active<>1 OR u.role<>'evaluator'")" = '0'

MYSQL_HISTFILE=/dev/null mariadb --database="$DB_NAME" --table --execute "
SELECT version, name FROM schema_migrations WHERE version=176;
SELECT COUNT(*) AS canonical_assignments FROM asset_evaluator_assignments;
SELECT COUNT(*) AS assets_without_assignment
FROM information_assets i
LEFT JOIN asset_evaluator_assignments a
  ON a.tenant_id=i.tenant_id AND a.asset_id=i.asset_id
WHERE a.asset_id IS NULL;
"

unset OPENIRN_MIGRATION_MYSQL_URL OPENIRN_API_MYSQL_URL
```

Une erreur à ce stade ne justifie pas de supprimer la nouvelle table : le DDL
MariaDB peut déjà être validé. Conserver l'ancien code, redémarrer l'API et
diagnostiquer. La migration est additive et réexécutable.

## 8. Sauvegarder puis remplacer les trois fichiers applicatifs

```bash
export ROLLBACK_DIR="/var/backups/openirn-api/migration-176-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 700 "$ROLLBACK_DIR"

declare -a DEPLOY_FILES=(
	'app/main.py'
	'app/database_contract.py'
	'sql/schema_mariadb.sql'
)

for rel in "${DEPLOY_FILES[@]}"; do
	install -d -o root -g root -m 700 "$ROLLBACK_DIR/$(dirname "$rel")"
	cp --archive "$APP_DIR/$rel" "$ROLLBACK_DIR/$rel"
done

(
	cd "$ROLLBACK_DIR"
	sha256sum "${DEPLOY_FILES[@]}" > SHA256SUMS
)

for rel in "${DEPLOY_FILES[@]}"; do
	target="$APP_DIR/$rel"
	owner="$(stat -c '%u' "$target")"
	group="$(stat -c '%g' "$target")"
	mode="$(stat -c '%a' "$target")"
	install -o "$owner" -g "$group" -m "$mode" \
		"$STAGED_API/$rel" "$target"
	cmp --silent "$STAGED_API/$rel" "$target"
done

"$APP_DIR/.venv/bin/python" -m py_compile \
	"$APP_DIR/app/database_contract.py" \
	"$APP_DIR/app/main.py" \
	"$APP_DIR/tools/migrate_mariadb.py"

systemctl start openirn-api
systemctl is-active --quiet openirn-api
```

## 9. Vérifications fonctionnelles

```bash
curl --fail --silent --show-error --max-time 10 \
	http://127.0.0.1:8091/health | jq -e \
	'.status == "ok" and .storage == "mariadb" and .authRequired == true'

curl --fail --silent --show-error --max-time 20 \
	http://127.0.0.1:8091/openapi.json \
	| jq -e '.paths["/inventory/assets/{asset_id}/evaluator"].patch'

UNAUTH_STATUS="$(curl --silent --show-error --max-time 10 \
	--output /tmp/openirn-m176-unauthorized.json \
	--write-out '%{http_code}' \
	--request PATCH \
	--header 'Content-Type: application/json' \
	--data '{"tenantId":"unauthorized","userId":""}' \
	http://127.0.0.1:8091/inventory/assets/unauthorized/evaluator)"
test "$UNAUTH_STATUS" = '403'

curl --fail --silent --show-error --max-time 20 \
	https://www.archoad.io/api/health | jq -e \
	'.status == "ok" and .storage == "mariadb" and .authRequired == true'

systemctl show openirn-api -p ActiveState -p SubState -p NRestarts --no-pager
journalctl -u openirn-api --since "$MAINTENANCE_START" \
	--priority=warning --no-pager
```

Le journal ne doit contenir ni erreur de schéma, ni boucle de redémarrage. Faire
ensuite un test authentifié avec un Pilote IRN : affecter un évaluateur à un
actif, ouvrir deux campagnes contenant cet actif et confirmer que les deux
exposent le même évaluateur.

## 10. Nettoyage du drill après validation

Les commandes suivantes sont destructrices, mais uniquement pour la base et les
deux comptes éphémères dont les noms sont validés explicitement ci-dessous. Ne
les exécuter qu'après la validation de la production.

```bash
test "$DRILL_DB" = 'openirn_restore_m176_test'

MYSQL_HISTFILE=/dev/null mariadb <<SQL
DROP DATABASE \`openirn_restore_m176_test\`;
DROP USER 'openirn_m176_migration'@'127.0.0.1';
DROP USER 'openirn_m176_runtime'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

rm -f /run/openirn-m176-drill.env \
	/run/openirn-m176-drill.ok \
	/run/openirn-m176-backup-started \
	/run/openirn-m176-final-backup-started \
	/tmp/openirn-m176-unauthorized.json
unset OPENIRN_M176_MIGRATION_URL OPENIRN_M176_RUNTIME_URL
```

## Retour arrière applicatif

Le retour arrière applicatif ne supprime pas la table 176 : elle est additive et
l'ancien code l'ignore. En cas d'échec du nouveau service :

```bash
systemctl stop openirn-api
test -n "${ROLLBACK_DIR:-}"
test -f "$ROLLBACK_DIR/SHA256SUMS"
(
	cd "$ROLLBACK_DIR"
	sha256sum --check SHA256SUMS
)

for rel in "${DEPLOY_FILES[@]}"; do
	cp --archive "$ROLLBACK_DIR/$rel" "$APP_DIR/$rel"
done

systemctl start openirn-api
systemctl is-active --quiet openirn-api
curl --fail --silent --show-error --max-time 10 \
	http://127.0.0.1:8091/health | jq .
```

Une restauration de la base n'est justifiée qu'en cas de corruption confirmée.
Elle écrase toutes les écritures postérieures au dump final et doit donc faire
l'objet d'une décision DBA séparée ; ne pas l'automatiser dans ce runbook.
