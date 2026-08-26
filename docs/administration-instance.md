---
title: "Administrer une instance OpenIRN"
subtitle: "Exploitation, sauvegarde, restauration, mise à jour et dépannage"
author: "Projet OpenIRN"
---

# Objet

Ce guide s’adresse à l’administrateur technique d’une instance OpenIRN. Il couvre le serveur Linux, MariaDB, Apache, l’API et le parc applicatif. Les commandes serveur sont prévues pour une session `root` ; elles n’utilisent pas `sudo`.

Adapte les noms DNS et versions à ton instance. Ne copie jamais dans un ticket ou un journal les fichiers `/etc/openirn-api*.env`, les PIN, les jetons de terminal, les codes d’enrôlement ou les secrets de signature.

# 1. Architecture à connaître

```text
Applications Android / Windows / Apple
                 |
              HTTPS/443
                 |
              Apache
                 |
       127.0.0.1:8091 seulement
                 |
        Uvicorn / FastAPI OpenIRN
                 |
       MariaDB sur l’hôte ou réseau privé
```

Répertoires et unités usuels :

| Élément | Emplacement |
|---|---|
| Version API active | `/opt/openirn-api` |
| Versions installées | `/opt/openirn-releases/vX.Y.Z` |
| Environnement runtime | `/etc/openirn-api.env` |
| Environnement migration | `/etc/openirn-api-migration.env` |
| Données et référentiels | `/var/lib/openirn-api` |
| Sauvegardes | `/var/lib/openirn-api/backups` |
| API | `openirn-api.service` |
| Sauvegarde | `openirn-api-backup.service` |
| Planification | `openirn-api-backup.timer` |

MariaDB est l’unique backend serveur. Le client ne conserve pas de données métier persistantes ; il conserve seulement les éléments nécessaires à la connexion, les préférences et le jeton terminal dans le stockage sécurisé de la plateforme.

# 2. Contrôle quotidien

## État des services

```bash
systemctl is-active mariadb apache2 openirn-api openirn-api-backup.timer
systemctl is-enabled mariadb apache2 openirn-api openirn-api-backup.timer
```

Toutes les unités doivent être `active`; les unités pérennes et le timer doivent être `enabled`.

## Santé interne et publique

```bash
curl --fail --silent --show-error http://127.0.0.1:8091/health | jq
curl --fail --silent --show-error https://openirn.example.org/api/health | jq
```

Contrôle les champs :

- `status` égal à `ok` ;
- `storage` égal à `mariadb` ;
- `authRequired` égal à `true` ;
- `authMode` égal à `server_session_with_role_policy`.

Un health `200` prouve la disponibilité de base, pas l’ensemble du parcours utilisateur. Complète-le régulièrement par une recette avec un compte et une campagne de test.

## Écoute réseau

```bash
ss -ltnp | grep -E ':(443|8091|3306)\b'
```

Attendu :

- Apache écoute sur les interfaces prévues en 443 ;
- Uvicorn écoute uniquement sur `127.0.0.1:8091` ;
- MariaDB n’est pas exposé publiquement.

## Erreurs récentes

```bash
journalctl -u openirn-api --since today --priority warning --no-pager
journalctl -u openirn-api-backup.service --since today --no-pager
tail -n 100 /var/log/apache2/openirn-api-error.log
```

Recherche notamment les redémarrages répétés, refus MariaDB, migrations manquantes, erreurs de sauvegarde, `AH01084`, `AH01097`, `Broken pipe`, `502` et `503`.

# 3. Contrôle hebdomadaire

## MariaDB

Exécute l’outil avec le compte runtime sans afficher l’URL :

```bash
cd /opt/openirn-api
(
	set -a
	. /etc/openirn-api.env
	set +a
	runuser -u www-data -- .venv/bin/python tools/check_runtime_backend.py
)
```

Vérifie aussi la taille des tables :

```bash
MYSQL_HISTFILE=/dev/null mariadb openirn -e \
	"SELECT table_name, table_rows, ROUND((data_length+index_length)/1024/1024,1) AS mib FROM information_schema.tables WHERE table_schema='openirn' ORDER BY data_length+index_length DESC;"
```

`table_rows` est une estimation InnoDB. Utilise-la pour détecter une évolution anormale, pas comme preuve comptable.

## Sauvegardes présentes

```bash
systemctl list-timers openirn-api-backup.timer --no-pager
find /var/lib/openirn-api/backups -maxdepth 1 -type f \
	-printf '%TY-%Tm-%Td %TH:%TM %s %f\n' | sort
```

Vérifie qu’une sauvegarde récente existe, que les trois fichiers associés sont présents et qu’une copie chiffrée a quitté l’hôte.

## Certificat TLS

```bash
openssl s_client -connect openirn.example.org:443 \
	-servername openirn.example.org </dev/null 2>/dev/null |
	openssl x509 -noout -subject -issuer -dates
```

Planifie le renouvellement avant expiration et teste le rechargement Apache.

# 4. Contrôle mensuel

- réalise une restauration complète dans une base vide ;
- examine les comptes actifs et leurs rôles ;
- révoque les sessions inutiles ;
- examine les terminaux inactifs ou inconnus ;
- contrôle les événements de sécurité et limitations répétées ;
- vérifie les releases et dépendances disponibles ;
- teste la mise à jour sur une instance ou un groupe pilote ;
- vérifie que la documentation PDF publiée correspond à la version utilisée.

# 5. Sauvegardes

## Sauvegarde planifiée

Le timer exécute une sauvegarde quotidienne à l’heure définie dans `openirn-api-backup.timer`. Contrôle son prochain passage :

```bash
systemctl list-timers openirn-api-backup.timer --all --no-pager
```

## Sauvegarde manuelle avant changement

```bash
systemctl start openirn-api-backup.service
systemctl is-failed openirn-api-backup.service
journalctl -u openirn-api-backup.service --since '10 minutes ago' --no-pager
```

`systemctl is-failed` doit répondre `inactive`, pas `failed`.

Identifie les fichiers récents :

```bash
find /var/lib/openirn-api/backups -maxdepth 1 -type f \
	-newermt '15 minutes ago' -printf '%f %s octets\n' | sort
```

Le manifeste HMAC détecte une modification accidentelle ou malveillante des fichiers, mais ne chiffre pas les données. Chiffre les copies hors site et limite leur accès.

## Rétention

`OPENIRN_API_BACKUP_KEEP` fixe le nombre de sauvegardes conservées localement. Ne réduis pas la rétention avant d’avoir confirmé les copies externes. Une suppression de sauvegarde est irréversible si aucune autre copie n’existe.

# 6. Exercice de restauration

La restauration officielle cible une **base vide distincte**. L’outil refuse par défaut la base source et une cible non vide.

## Préparer une cible de test

Choisis un nom daté, puis ouvre MariaDB sans historique :

```bash
MYSQL_HISTFILE=/dev/null mariadb
```

Adapte les valeurs :

```sql
CREATE DATABASE openirn_restore_YYYYMMDD
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'openirn_restore'@'localhost'
  IDENTIFIED BY 'MOT_DE_PASSE_À_REMPLACER';
GRANT ALL PRIVILEGES ON openirn_restore_YYYYMMDD.*
  TO 'openirn_restore'@'localhost';
FLUSH PRIVILEGES;
```

Crée un fichier temporaire protégé :

```bash
install -o root -g root -m 600 /dev/null /etc/openirn-api-restore.env
vim /etc/openirn-api-restore.env
```

Contenu :

```text
OPENIRN_RESTORE_MYSQL_URL=mysql+pymysql://openirn_restore:MOT_DE_PASSE_À_REMPLACER@127.0.0.1:3306/openirn_restore_YYYYMMDD?charset=utf8mb4
```

## Vérifier et restaurer

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

Examine le rapport : migrations, nombres de lignes, clés étrangères et catégories d’orphelins doivent être valides.

## Détruire la cible de test

Les commandes suivantes suppriment définitivement la base restaurée et son compte. Ne les exécute qu’après validation du rapport et de la cible exacte :

```bash
MYSQL_HISTFILE=/dev/null mariadb
```

```sql
DROP DATABASE openirn_restore_YYYYMMDD;
DROP USER 'openirn_restore'@'localhost';
```

Puis supprime le fichier de connexion temporaire :

```bash
rm /etc/openirn-api-restore.env
```

# 7. Reprise après perte de la base active

Une restauration réelle est une opération de crise :

1. arrête l’API pour stopper les écritures ;
2. conserve la base défaillante sans la modifier ;
3. restaure dans une nouvelle base vide ;
4. valide le rapport de restauration ;
5. modifie l’URL runtime vers la nouvelle base ;
6. démarre l’API ;
7. exécute les contrôles interne et public ;
8. réalise une recette fonctionnelle ;
9. ne supprime l’ancienne base qu’après décision formelle et expiration du délai de retour arrière.

Ne restaure jamais directement par-dessus une base active ou partiellement remplie.

# 8. Mise à jour du serveur API

## Préparer

1. lis les notes de release ;
2. vérifie la compatibilité client/API ;
3. contrôle l’espace disque ;
4. réalise et externalise une sauvegarde ;
5. annonce la fenêtre de maintenance ;
6. conserve le chemin de la version actuellement active.

```bash
df -h /opt /var/lib/openirn-api
readlink -f /opt/openirn-api
systemctl start openirn-api-backup.service
journalctl -u openirn-api-backup.service --since '10 minutes ago' --no-pager
```

## Télécharger la nouvelle version

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
	"$release_dir/app/main.py" \
	"$release_dir/tools/"*.py
```

## Migrer et basculer

L’arrêt interrompt les utilisateurs et les synchronisations. Vérifie la fenêtre de maintenance avant cette commande :

```bash
systemctl stop openirn-api
```

Applique les migrations avec le code de la nouvelle version :

```bash
cd "$release_dir"
set -a
. /etc/openirn-api.env
. /etc/openirn-api-migration.env
set +a
.venv/bin/python tools/migrate_mariadb.py
unset OPENIRN_MIGRATION_MYSQL_URL OPENIRN_API_MYSQL_URL
```

La commande suivante remplace le lien symbolique actif. Le retour au code précédent restera possible, mais une migration de données peut ne pas être réversible ; la sauvegarde est donc obligatoire :

```bash
ln -sfn "$release_dir" /opt/openirn-api
systemctl daemon-reload
systemctl start openirn-api
systemctl is-active openirn-api
```

## Recette post-mise à jour

```bash
journalctl -u openirn-api --since '10 minutes ago' --no-pager
curl --fail --silent --show-error http://127.0.0.1:8091/health | jq
curl --fail --silent --show-error https://openirn.example.org/api/health | jq
```

Puis vérifie avec un terminal pilote :

- choix de l’espace ;
- ouverture et verrouillage de session ;
- référentiel ;
- campagne de recette ;
- écriture autorisée ;
- synchronisation sur un second terminal ;
- synthèse et export ;
- administration selon le rôle.

# 9. Retour arrière du code

Si la nouvelle version échoue avant toute migration irréversible, repointe le lien vers la version précédente :

```bash
systemctl stop openirn-api
ln -sfn /opt/openirn-releases/vVERSION_PRÉCÉDENTE /opt/openirn-api
systemctl start openirn-api
systemctl is-active openirn-api
```

Si le schéma ou les données ont changé, ne démarre pas aveuglément l’ancien code. Restaure la sauvegarde dans une nouvelle base, valide-la puis bascule l’URL runtime conformément au plan de reprise.

# 10. Mise à jour des applications

1. vérifie les empreintes de la release ;
2. déploie Android et Windows sur un groupe pilote ;
3. mets à jour en place, sans désinstallation ;
4. vérifie que l’enrôlement a été conservé ;
5. teste les rôles représentatifs ;
6. surveille l’API et le journal sécurité ;
7. élargis la vague.

Les releases actuelles ne publient pas d’artefacts Apple signés. Ne considère pas macOS/iOS comme déployés tant qu’une chaîne Developer ID/TestFlight ou MDM n’a pas été validée.

# 11. Dépannage par symptôme

## API inactive

```bash
systemctl status openirn-api --no-pager
journalctl -u openirn-api -n 150 --no-pager
```

Vérifie ensuite :

```bash
readlink -f /opt/openirn-api
stat -c '%U %G %a %n' /etc/openirn-api.env
cd /opt/openirn-api
.venv/bin/python -m py_compile app/main.py app/database_contract.py
```

Causes courantes : dépendance absente, URL MariaDB incorrecte, migration manquante, privilèges runtime trop larges ou fichier d’environnement absent.

## Health interne OK, public en 502

```bash
apache2ctl configtest
systemctl status apache2 --no-pager
tail -n 150 /var/log/apache2/openirn-api-error.log
curl --verbose http://127.0.0.1:8091/health
```

Vérifie `ProxyPass`, le chemin `/api/`, le certificat et les règles réseau locales.

## Réponse 413

Une réponse `413` signifie que le corps dépasse une limite. Les valeurs par défaut sont 1 Mio pour une requête ordinaire, 16 Mio pour la synchronisation et 5 Mio pour un import XLSX, avec 64 Mio décompressés au maximum.

Ne relève pas globalement la limite sans identifier la route et le besoin. Vérifie aussi `LimitRequestBody` côté Apache.

## Réponse 429

Une réponse `429` sur l’enrôlement indique une limitation anti-abus. Attends la durée `Retry-After`, vérifie l’adresse client remontée par le proxy et recherche une répétition anormale dans le journal sécurité.

## Terminal non autorisé ou 403

Vérifie dans cet ordre :

1. espace sélectionné ;
2. présence du terminal dans cet espace ;
3. statut actif et absence de révocation ;
4. session utilisateur valide ;
5. rôle compatible avec l’action ;
6. heure du terminal et du serveur.

Un terminal autorisé dans un espace ne l’est pas automatiquement dans les autres.

## Session expirée

Demande à l’utilisateur de revenir à l’accueil et de se déverrouiller. Si le problème se répète immédiatement :

```bash
timedatectl status
journalctl -u openirn-api --since '15 minutes ago' --no-pager
```

Vérifie les paramètres `OPENIRN_SESSION_TTL_MINUTES` et `OPENIRN_SESSION_IDLE_TIMEOUT_MINUTES` sans afficher le reste du fichier d’environnement.

## Sauvegarde en échec

```bash
systemctl status openirn-api-backup.service --no-pager
journalctl -u openirn-api-backup.service -n 150 --no-pager
namei -l /var/lib/openirn-api/backups
df -h /var/lib/openirn-api
```

Vérifie le binaire de dump, les droits `www-data`, l’espace disque et la présence d’un secret de signature d’au moins 32 caractères.

## Synchronisation incohérente

- suspends les modifications concurrentes sur la campagne concernée ;
- note la campagne, l’espace, les terminaux et l’heure ;
- consulte **Administration → Historique / conflits** ;
- compare la révision courante et les révisions précédentes ;
- ne restaure une révision qu’après avoir compris les données perdues par ce choix.

La restauration de campagne crée une nouvelle évolution serveur ; elle ne remplace pas une restauration MariaDB globale.

# 12. Administration de sécurité dans l’application

## Utilisateurs

- désactive rapidement les comptes sortants ;
- vérifie périodiquement les administrateurs et Pilotes IRN ;
- attribue un PIN temporaire non trivial uniquement lorsque nécessaire ;
- confirme que le changement est exigé à la prochaine connexion ;
- utilise des comptes nominatifs.

## Sessions

Dans **Administration → Sessions serveur**, révoque les sessions inconnues, anciennes ou associées à un incident. Une réinitialisation de PIN par un administrateur révoque les sessions existantes de l’utilisateur ciblé.

## Terminaux

- vérifie nom, plateforme, espace et dernière activité ;
- approuve une demande seulement après confirmation du demandeur ;
- révoque immédiatement un terminal perdu ;
- supprime les autorisations devenues inutiles ;
- conserve le terminal dans le seul périmètre nécessaire.

## Journal sécurité

Recherche les échecs répétés, limitations, créations de codes, enrôlements, révocations, changements de PIN, restaurations et opérations de maintenance. Le journal ne doit contenir ni PIN ni jeton complet.

# 13. Gestion des espaces de travail

Chaque espace isole utilisateurs, campagnes, inventaire et autorisations de terminal. Le référentiel officiel est global et partagé.

Lors de la création d’un espace :

1. choisis un nom métier non ambigu ;
2. désigne un Pilote IRN initial ;
3. vérifie ses coordonnées et son rôle ;
4. enrôle explicitement les terminaux nécessaires ;
5. crée ou importe l’inventaire ;
6. réalise une campagne de recette.

La suppression d’un espace est destructive et peut supprimer ses données rattachées. Exporte ce qui doit être conservé, réalise une sauvegarde vérifiée et confirme l’identifiant exact avant l’action.

# 14. Référentiel officiel

L’administrateur utilise **Administration → Référentiel officiel aDRI** pour :

- vérifier la version distante ;
- examiner les métadonnées et le rapport de validation ;
- importer la version courante ;
- consulter l’historique.

Avant une mise à jour, sauvegarde l’instance et teste la version sur une campagne de recette. Ne suppose pas que la version `v1.1` restera toujours la version courante.

# 15. Capacité et nettoyage

Surveille :

```bash
df -h
du -sh /var/lib/openirn-api /var/lib/openirn-api/backups /opt/openirn-releases/*
journalctl --disk-usage
```

Ne supprime pas directement des lignes MariaDB ni des fichiers de sauvegarde sans passer par une procédure approuvée. Pour les anciennes versions API, conserve au minimum la version active et la version de retour arrière validée. Vérifie qu’aucun processus n’utilise une version avant de la retirer.

# 16. Fiche d’incident

Collecte sans secret :

- date, heure et fuseau ;
- espace concerné ;
- rôle de l’utilisateur ;
- plateforme et version de l’application ;
- action exacte ;
- code HTTP et message visible ;
- état des services ;
- extraits de journaux limités à la fenêtre de l’incident ;
- dernière sauvegarde connue ;
- changements récents de serveur ou d’application.

Ne collecte pas le PIN, le code d’enrôlement, l’en-tête `Authorization`, un fichier `.env`, une clé privée ou un dump complet dans un ticket.

# 17. Checklist de changement

Avant :

- [ ] périmètre et objectif validés ;
- [ ] version et notes de release vérifiées ;
- [ ] sauvegarde récente créée et externalisée ;
- [ ] retour arrière défini ;
- [ ] groupe pilote identifié ;
- [ ] fenêtre annoncée.

Après :

- [ ] services actifs et activés ;
- [ ] health interne et public en succès ;
- [ ] aucun redémarrage en boucle ;
- [ ] connexion et changement d’espace testés ;
- [ ] lecture et écriture de recette testées ;
- [ ] synchronisation multi-terminal testée ;
- [ ] sauvegarde post-changement créée ;
- [ ] résultat et limites consignés sans secret.
