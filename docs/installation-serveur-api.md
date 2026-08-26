---
title: "Installer et initialiser le serveur OpenIRN"
subtitle: "API FastAPI, MariaDB, Apache et premier accès"
author: "Projet OpenIRN"
---

# Objet et périmètre

Ce document installe une instance neuve de l’API OpenIRN derrière Apache, avec MariaDB comme unique base serveur. Il est rédigé comme une recette : exécute chaque étape dans l’ordre et ne poursuis que lorsque le contrôle annoncé réussit.

La recette cible un serveur **Debian 13** administré avec le compte `root`. Elle utilise :

- Python 3 et un environnement virtuel dédié ;
- MariaDB avec deux comptes distincts : migration et exploitation ;
- Uvicorn lié uniquement à `127.0.0.1:8091` ;
- Apache en frontal HTTPS sous le chemin public `/api/` ;
- systemd pour l’API et les sauvegardes quotidiennes ;
- une version publiée d’OpenIRN identifiée par un tag Git `vX.Y.Z`.

> Les commandes ne contiennent aucun secret réel. Remplace les noms de domaine, le tag et les valeurs marquées `À_REMPLACER`. N’inscris jamais un mot de passe ou un secret dans le dépôt, un ticket ou un historique de commandes.

# 1. Préparer les informations

Choisis les valeurs suivantes avant de commencer :

| Paramètre | Exemple documentaire | Usage |
|---|---|---|
| Nom DNS | `openirn.example.org` | URL publique de l’API |
| Tag OpenIRN | `vX.Y.Z` | version immuable à déployer |
| Base MariaDB | `openirn` | données de l’instance |
| Espace d’administration | `openirn-admin` | espace source de l’administrateur solution |
| Répertoire des versions | `/opt/openirn-releases` | installations immuables |
| Lien actif | `/opt/openirn-api` | version exécutée |
| Données | `/var/lib/openirn-api` | référentiels et sauvegardes |

Déclare uniquement les valeurs non sensibles :

```bash
export OPENIRN_HOST='openirn.example.org'
export OPENIRN_TAG='vX.Y.Z'
export OPENIRN_ADMIN_TENANT='openirn-admin'
```

Bloque la suite si le tag est encore un exemple :

```bash
test "$OPENIRN_TAG" != 'vX.Y.Z' || {
	echo 'Définis OPENIRN_TAG avec un tag publié' >&2
	exit 1
}
```

# 2. Vérifier le serveur et le DNS

Contrôle le système :

```bash
cat /etc/os-release
uname -m
hostnamectl
```

Résultat attendu : Debian 13, architecture compatible avec Python et MariaDB, horloge correctement synchronisée.

Contrôle l’heure :

```bash
timedatectl status
```

Le champ `System clock synchronized` doit être `yes`. Les sessions et codes temporaires OpenIRN dépendent d’une heure correcte.

Depuis un poste externe, le nom DNS doit pointer vers le serveur :

```bash
dig +short "$OPENIRN_HOST" A
dig +short "$OPENIRN_HOST" AAAA
```

N’ouvre publiquement que TCP/443. Le port MariaDB 3306 et le port Uvicorn 8091 doivent rester locaux ou filtrés.

# 3. Installer les prérequis

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

Contrôle les services et versions réellement installés :

```bash
python3 --version
mariadb --version
apache2ctl -v
systemctl is-active mariadb
systemctl is-active apache2
```

Les deux dernières commandes doivent répondre `active`.

# 4. Télécharger une version OpenIRN

Crée les répertoires :

```bash
install -d -o root -g root -m 755 /opt/openirn-releases
install -d -o www-data -g www-data -m 750 /var/lib/openirn-api
install -d -o www-data -g www-data -m 750 /var/lib/openirn-api/backups
```

Télécharge l’archive source correspondant au tag :

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

Déploie seulement le serveur :

```bash
release_dir="/opt/openirn-releases/${OPENIRN_TAG}"
test ! -e "$release_dir"
install -d -o root -g root -m 755 "$release_dir"
cp -a "$source_root/server/openirn-api/." "$release_dir/"
chown -R root:root "$release_dir"
ln -s "$release_dir" /opt/openirn-api
```

Contrôle le lien et les fichiers :

```bash
readlink -f /opt/openirn-api
test -f /opt/openirn-api/requirements-mariadb.txt
test -f /opt/openirn-api/sql/schema_mariadb.sql
```

Le lien doit viser exactement `/opt/openirn-releases/$OPENIRN_TAG`.

# 5. Créer l’environnement Python

```bash
python3 -m venv /opt/openirn-api/.venv
/opt/openirn-api/.venv/bin/python -m pip install --upgrade pip
/opt/openirn-api/.venv/bin/python -m pip install \
	--requirement /opt/openirn-api/requirements-mariadb.txt
```

Contrôle les imports sans démarrer l’API :

```bash
cd /opt/openirn-api
.venv/bin/python -m py_compile app/database_contract.py app/main.py tools/*.py
.venv/bin/python -c 'import fastapi, pymysql, uvicorn; print("Dépendances Python OK")'
```

# 6. Créer la base et séparer les privilèges

Génère deux mots de passe aléatoires distincts et conserve-les dans un gestionnaire de secrets. Les valeurs hexadécimales évitent les problèmes d’encodage dans les URL MariaDB :

```bash
openssl rand -hex 32
openssl rand -hex 32
```

Ouvre MariaDB sans conserver l’historique SQL :

```bash
MYSQL_HISTFILE=/dev/null mariadb
```

Adapte puis exécute :

```sql
CREATE DATABASE IF NOT EXISTS openirn
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'openirn_runtime'@'localhost'
  IDENTIFIED BY 'MOT_DE_PASSE_RUNTIME_À_REMPLACER';
CREATE USER IF NOT EXISTS 'openirn_migration'@'localhost'
  IDENTIFIED BY 'MOT_DE_PASSE_MIGRATION_À_REMPLACER';

GRANT SELECT, INSERT, UPDATE, DELETE
  ON openirn.* TO 'openirn_runtime'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP, REFERENCES
  ON openirn.* TO 'openirn_migration'@'localhost';
FLUSH PRIVILEGES;

SHOW GRANTS FOR 'openirn_runtime'@'localhost';
SHOW GRANTS FOR 'openirn_migration'@'localhost';
```

Le compte runtime ne doit posséder ni `CREATE`, ni `ALTER`, ni `DROP`, ni `INDEX`, ni `GRANT OPTION`.

# 7. Créer les secrets de déploiement

Génère séparément :

```bash
openssl rand -hex 32
openssl rand -hex 32
```

La première valeur servira à signer les manifestes de sauvegarde ; la seconde à hacher les codes d’enrôlement. Une rotation du secret d’enrôlement invalide les codes temporaires non consommés.

Crée le fichier runtime, lisible uniquement par `root` :

```bash
install -o root -g root -m 600 /dev/null /etc/openirn-api.env
vim /etc/openirn-api.env
```

Contenu minimal :

```text
OPENIRN_API_MYSQL_URL=mysql+pymysql://openirn_runtime:MOT_DE_PASSE_RUNTIME_À_REMPLACER@127.0.0.1:3306/openirn?charset=utf8mb4
OPENIRN_API_DATA_DIR=/var/lib/openirn-api
OPENIRN_API_BACKUP_DIR=/var/lib/openirn-api/backups
OPENIRN_API_BACKUP_KEEP=30
OPENIRN_API_BACKUP_AUTO_ENABLED=true
OPENIRN_API_BACKUP_PROTECTIVE_ENABLED=true
OPENIRN_API_BACKUP_SIGNATURE_SECRET=SECRET_SAUVEGARDE_À_REMPLACER
OPENIRN_ENROLLMENT_CODE_SECRET=SECRET_ENROLEMENT_À_REMPLACER
OPENIRN_SOLUTION_ADMIN_TENANT_ID=openirn-admin
OPENIRN_TRUSTED_PROXY_CIDRS=127.0.0.1/32,::1/128
OPENIRN_SESSION_TTL_MINUTES=480
OPENIRN_SESSION_IDLE_TIMEOUT_MINUTES=30
OPENIRN_LEGACY_GLOBAL_BEARER_ENABLED=false
```

Crée séparément le fichier de migration :

```bash
install -o root -g root -m 600 /dev/null /etc/openirn-api-migration.env
vim /etc/openirn-api-migration.env
```

Contenu :

```text
OPENIRN_MIGRATION_MYSQL_URL=mysql+pymysql://openirn_migration:MOT_DE_PASSE_MIGRATION_À_REMPLACER@127.0.0.1:3306/openirn?charset=utf8mb4
```

Contrôle les permissions sans afficher les valeurs :

```bash
stat -c '%U %G %a %n' /etc/openirn-api.env /etc/openirn-api-migration.env
```

Résultat attendu : `root root 600` pour les deux fichiers.

# 8. Appliquer le schéma MariaDB

L’API n’applique pas de DDL au démarrage. Charge temporairement les deux fichiers puis exécute l’outil dédié :

```bash
cd /opt/openirn-api
set -a
. /etc/openirn-api.env
. /etc/openirn-api-migration.env
set +a
.venv/bin/python tools/migrate_mariadb.py
unset OPENIRN_MIGRATION_MYSQL_URL OPENIRN_API_MYSQL_URL
```

Résultat attendu : migrations appliquées, comptes de migration et runtime distincts, privilèges runtime limités à `SELECT`, `INSERT`, `UPDATE`, `DELETE`.

Contrôle la base avec le compte runtime :

```bash
(
	set -a
	. /etc/openirn-api.env
	set +a
	/opt/openirn-api/.venv/bin/python /opt/openirn-api/tools/check_mariadb_readiness.py
)
```

Toutes les tables listées doivent être lisibles et aucune ne doit être signalée manquante.

# 9. Installer et démarrer l’unité systemd

```bash
install -o root -g root -m 644 \
	/opt/openirn-api/systemd/openirn-api.service \
	/etc/systemd/system/openirn-api.service
systemctl daemon-reload
systemctl enable --now openirn-api.service
```

Contrôle :

```bash
systemctl is-active openirn-api.service
systemctl is-enabled openirn-api.service
ss -ltnp | grep '127.0.0.1:8091'
curl --fail --silent --show-error http://127.0.0.1:8091/health | jq
```

Le JSON doit notamment annoncer :

```json
{
  "status": "ok",
  "storage": "mariadb",
  "authRequired": true,
  "authMode": "server_session_with_role_policy"
}
```

En cas d’échec :

```bash
journalctl -u openirn-api.service -n 100 --no-pager
```

# 10. Publier l’API avec Apache et TLS

Active les modules nécessaires :

```bash
a2enmod headers proxy proxy_http ssl
```

Installe d’abord un certificat TLS valide pour `$OPENIRN_HOST` selon la procédure de ton organisation. Les chemins ci-dessous sont des exemples à adapter.

Crée le virtual host :

```bash
vim /etc/apache2/sites-available/openirn-api.conf
```

Contenu :

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

Remplace le nom DNS et les chemins de certificat, puis vérifie et active :

```bash
apache2ctl configtest
a2ensite openirn-api.conf
systemctl reload apache2
systemctl is-active apache2
```

Contrôle depuis un poste qui résout le DNS :

```bash
curl --fail --silent --show-error "https://${OPENIRN_HOST}/api/health" | jq
```

Le port Uvicorn ne doit pas être joignable depuis l’extérieur. Ne configure `OPENIRN_TRUSTED_PROXY_CIDRS` qu’avec l’adresse du pair qui se connecte réellement à Uvicorn.

# 11. Installer les sauvegardes automatiques

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

Contrôle :

```bash
systemctl list-timers openirn-api-backup.timer --no-pager
journalctl -u openirn-api-backup.service -n 50 --no-pager
find /var/lib/openirn-api/backups -maxdepth 1 -type f -printf '%f %s octets\n' | sort
```

Une sauvegarde valide comporte le dump, son empreinte SHA-256 et son manifeste signé. Une copie hors de l’hôte reste indispensable.

# 12. Créer le premier administrateur solution

Cette étape s’effectue une seule fois, après les migrations. L’outil refuse d’agir si un administrateur actif existe déjà dans l’espace cible.

```bash
cd /opt/openirn-api
(
	set -a
	. /etc/openirn-api.env
	set +a
	.venv/bin/python tools/create_superuser.py \
		--tenant "$OPENIRN_ADMIN_TENANT" \
		--tenant-name 'Administration OpenIRN' \
		--first-name 'Prénom' \
		--last-name 'Nom' \
		--email 'admin@example.org'
)
```

Saisis deux fois un PIN temporaire non trivial. Il ne s’affiche pas et ne doit pas être placé dans la ligne de commande. OpenIRN imposera son remplacement à la première connexion.

Contrôle uniquement le nombre et le rôle, sans lire le hash :

```bash
MYSQL_HISTFILE=/dev/null mariadb openirn -e \
	"SELECT tenant_id,email,role,active FROM users WHERE role='administrator';"
```

Recharge l’API pour réconcilier l’administrateur solution avec les espaces déjà présents :

```bash
systemctl restart openirn-api
systemctl is-active openirn-api
```

# 13. Amorcer le premier terminal

Liste les espaces existants :

```bash
cd /opt/openirn-api
(
	set -a
	. /etc/openirn-api.env
	set +a
	.venv/bin/python tools/create_bootstrap_enrollment.py --list-tenants
)
```

Crée un code à usage unique valable dix minutes :

```bash
(
	set -a
	. /etc/openirn-api.env
	set +a
	.venv/bin/python tools/create_bootstrap_enrollment.py \
		--tenant "$OPENIRN_ADMIN_TENANT" \
		--label 'Premier terminal OpenIRN' \
		--expires 10
)
```

Dans l’application installée sur le premier poste :

1. Choisis l’espace d’administration.
2. Ouvre **Autoriser ce terminal**.
3. Saisis le code affiché par l’outil.
4. Déverrouille OpenIRN avec le compte administrateur et son PIN temporaire.
5. Choisis immédiatement un nouveau PIN personnel non trivial.

Le code est à usage unique. Ne le conserve pas après consommation.

# 14. Charger le référentiel officiel

Avec la session administrateur ouverte :

1. Ouvre **Administration**.
2. Ouvre **Référentiel officiel aDRI**.
3. Lance **Vérifier**.
4. Examine la version, la source et le rapport de validation.
5. Installe la version détectée si elle correspond à la version officielle attendue.

Reviens à l’accueil puis ouvre **Référentiel aDRI IRN**. Les piliers et critères doivent s’afficher. Ne présente pas OpenIRN comme une certification officielle : l’application exploite le référentiel publié séparément par l’aDRI/DRI.

# 15. Recette finale

Exécute ces contrôles :

```bash
systemctl is-active mariadb apache2 openirn-api openirn-api-backup.timer
curl --fail --silent --show-error http://127.0.0.1:8091/health | jq
curl --fail --silent --show-error "https://${OPENIRN_HOST}/api/health" | jq
journalctl -u openirn-api --since '15 minutes ago' --no-pager
journalctl -u openirn-api-backup.service -n 50 --no-pager
```

La mise en service est terminée lorsque :

- MariaDB, Apache, l’API et le timer sont actifs ;
- l’API n’écoute que sur `127.0.0.1:8091` ;
- le health interne et le health HTTPS répondent `200` ;
- le premier terminal est enrôlé dans le bon espace ;
- l’administrateur a remplacé son PIN temporaire ;
- le référentiel officiel est installé et consultable ;
- une sauvegarde signée a été produite et copiée hors de l’hôte.

# Dépannage rapide de l’installation

| Symptôme | Contrôle | Cause fréquente |
|---|---|---|
| L’API ne démarre pas | `journalctl -u openirn-api -n 100` | migration manquante ou privilèges runtime trop larges |
| `502` dans Apache | `curl http://127.0.0.1:8091/health` | Uvicorn arrêté ou mauvais `ProxyPass` |
| `403` dans l’application | vérifier espace, terminal et session | terminal non enrôlé dans cet espace ou session expirée |
| Code d’enrôlement refusé | vérifier heure et durée du code | code expiré, consommé ou secret d’enrôlement différent |
| Sauvegarde refusée | journal de l’unité backup | secret de signature trop court ou droits du répertoire |
| Référentiel absent | écran Référentiel officiel | import non effectué ou accès sortant GitLab indisponible |
