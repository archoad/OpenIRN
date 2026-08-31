---
title: "Administrer une instance OpenIRN"
subtitle: "Exploitation, sauvegarde, restauration, mise à jour et dépannage"
author: "Projet OpenIRN"
---

# Objet

Ce guide s'adresse à l'administrateur technique d'une instance OpenIRN. Il couvre le serveur Linux, MariaDB, Apache, l'API et le parc applicatif. Les commandes serveur sont prévues pour une session `root`.

Adapter les noms DNS et versions à votre instance. Ne jamais copier dans un ticket ou un journal les fichiers `/etc/openirn-api*.env`, les PIN, les jetons de terminal, les codes d'enrôlement ou les secrets de signature.

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
       MariaDB sur l'hôte ou réseau privé
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
| Journal API ECS/NDJSON | `/var/lib/openirn-api/logs/api-access.ndjson` |
| Journal sécurité ECS/NDJSON | `/var/lib/openirn-api/logs/security.ndjson` |
| Journal exploitation ECS/NDJSON | `/var/lib/openirn-api/logs/operations.ndjson` |
| API | `openirn-api.service` |
| Sauvegarde | `openirn-api-backup.service` |
| Planification | `openirn-api-backup.timer` |

MariaDB est l'unique backend serveur. Le client ne conserve pas de données métier persistantes, il conserve seulement les éléments nécessaires à la connexion, les préférences et le jeton terminal dans le stockage sécurisé de la plateforme.

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

Contrôler les champs :

- `status` égal à `ok` ;
- `storage` égal à `mariadb` ;
- `authRequired` égal à `true` ;
- `authMode` égal à `server_session_with_role_policy`.

Un health `200` prouve la disponibilité de base, pas l'ensemble du parcours utilisateur. Compléter régulièrement ce contrôle par une recette avec un compte et une campagne de test.

## Écoute réseau

```bash
ss -ltnp | grep -E ':(443|8091|3306)\b'
```

Attendu :

- Apache écoute sur les interfaces prévues en 443 ;
- Uvicorn écoute uniquement sur `127.0.0.1:8091` ;
- MariaDB n'est pas exposé publiquement.

## Erreurs récentes

```bash
journalctl -u openirn-api --since today --priority warning --no-pager
journalctl -u openirn-api-backup.service --since today --no-pager
tail -n 100 /var/log/apache2/openirn-api-error.log
```

Rechercher notamment les redémarrages répétés, refus MariaDB, migrations manquantes, erreurs de sauvegarde, `AH01084`, `AH01097`, `Broken pipe`, `502` et `503`.

## Trafic et latence de l'API

Le journal structuré de l'API produit exactement un événement par requête et ajoute l'en-tête `X-Request-ID` aux réponses traitées par le middleware. Vérifier les derniers événements sans modifier le fichier :

```bash
tail -n 20 /var/lib/openirn-api/logs/api-access.ndjson | jq -c \
	'{timestamp:."@timestamp", route:.url.path, status:.http.response.status_code, duration_ms:(.event.duration / 1000000), trace_id:.trace.id}'
```

Contrôler en priorité les statuts `5xx`, la hausse des `4xx` et les routes dont la durée augmente. `event.duration` est exprimé en nanosecondes. `url.path` contient le modèle de route FastAPI, par exemple `/campaigns/{campaign_id}`, jamais l'identifiant réel. Un chemin non reconnu devient `/__unmatched__`. Le journal ne contient ni corps, ni query string, ni en-tête, ni adresse cliente, ni identifiant métier brut.

Après authentification, `device.id` et `organization.id` sont des pseudonymes
HMAC utilisables pour compter les clients et tenants actifs sans journaliser
leurs identifiants réels. `openirn.client.platform` est la plateforme du terminal
enregistrée côté serveur.

## Événements de sécurité

Le journal de sécurité est séparé du journal d'accès. Afficher ses derniers événements sans exposer les pseudonymes dans la sortie :

```bash
tail -n 50 /var/lib/openirn-api/logs/security.ndjson | jq -c \
	'{timestamp:."@timestamp", action:.event.action, outcome:.event.outcome, severity:.event.severity, reason:.openirn.security.reason, trace_id:.trace.id}'
```

Surveiller en priorité `authorization.denied`, `auth.failed`, les limitations, créations ou consommations de codes d'enrôlement, révocations de sessions ou terminaux et changements de privilèges. `trace.id` permet de retrouver la requête correspondante dans `api-access.ndjson` ou Kibana. Les champs `organization.id`, `user.id`, `device.id` et les champs sous `openirn.security` sont des pseudonymes HMAC, jamais les valeurs métier brutes. Ne pas faire tourner `OPENIRN_API_OBSERVABILITY_HASH_SECRET` lors d'une maintenance courante : sa rotation empêche de corréler un même acteur avant et après la rotation.

## Événements d'exploitation

Vérifier les démarrages et les sauvegardes sans afficher de métadonnée sensible :

```bash
tail -n 50 /var/lib/openirn-api/logs/operations.ndjson | jq -c \
	'{timestamp:."@timestamp", action:.event.action, outcome:.event.outcome, version:.service.version, automatic:.openirn.operation.automatic}'
```

Les actions attendues sont `service.started`, `backup.created` et
`backup.failed`. Le journal ne contient ni chemin, ni nom, ni empreinte de
fichier, ni secret de signature.

## Dashboard Kibana OpenIRN

Le dashboard **OpenIRN — Supervision opérationnelle** est organisé en six sections : **Synthèse**, **Usage**, **Performance**, **Sécurité**, **Infrastructure** et **Exploitation**. Il couvre la disponibilité et les sauvegardes, les usages pseudonymisés, les latences p50/p95/p99, Apache, l'audit OpenIRN, les ressources système, MariaDB, systemd, TLS et la version déployée. Sa période initiale est de 24 heures et son actualisation automatique d'une minute.

Interpréter en priorité les objectifs affichés dans son bandeau :

- disponibilité synthétique supérieure ou égale à 99,9 % ;
- latence API p95 inférieure à 250 ms ;
- aucune réponse HTTP `5xx` ;
- dernière sauvegarde réussie depuis moins de 26 heures et aucun échec récent ;
- CPU inférieur à 85 %, mémoire et partition racine inférieures à 90 % et 85 % ;
- swap inférieur à 50 %, services systemd actifs et workers Apache sous 90 % ;
- certificat TLS valide plus de 30 jours ;
- absence de hausse durable des connexions, threads actifs ou connexions avortées MariaDB.

Les refus attendus, comme une requête sans session, augmentent les compteurs `403` et `authorization.denied` sans constituer seuls un incident. Corréler une hausse avec les motifs de sécurité, les pseudonymes de source et `trace.id`. Ces pseudonymes servent uniquement au regroupement technique et ne doivent pas être utilisés pour tenter de réidentifier un utilisateur.

La définition reproductible du dashboard se trouve dans `monitoring/kibana/openirn-api-health-security.json`. La procédure de déploiement portable est documentée dans `monitoring/kibana/README.md`. Elle exige la valeur ECS `host.name` de l'hôte à superviser et accepte tous les namespaces Fleet correspondant aux motifs documentés : journaux OpenIRN et Apache, Synthetics, métriques System, Apache Status, Linux systemd et MariaDB. L'opération `PUT` remplace entièrement le dashboard portant l'identifiant `openirn-api-health-security` : relire le diff JSON avant chaque redéploiement.

# 3. Contrôle hebdomadaire

## MariaDB

Exécuter l'outil avec le compte runtime sans afficher l'URL :

```bash
cd /opt/openirn-api
(
	set -a
	. /etc/openirn-api.env
	set +a
	runuser -u www-data -- .venv/bin/python tools/check_runtime_backend.py
)
```

Vérifier la taille des tables :

```bash
MYSQL_HISTFILE=/dev/null mariadb openirn -e \
	"SELECT table_name, table_rows, ROUND((data_length+index_length)/1024/1024,1) AS mib FROM information_schema.tables WHERE table_schema='openirn' ORDER BY data_length+index_length DESC;"
```

`table_rows` est une estimation InnoDB. L'utiliser pour détecter une évolution anormale, pas comme preuve comptable.

## Sauvegardes présentes

```bash
systemctl list-timers openirn-api-backup.timer --no-pager
find /var/lib/openirn-api/backups -maxdepth 1 -type f \
	-printf '%TY-%Tm-%Td %TH:%TM %s %f\n' | sort
```

Vérifier qu'une sauvegarde récente existe, que les trois fichiers associés sont présents et qu'une copie chiffrée a quitté l'hôte.

## Certificat TLS

```bash
openssl s_client -connect openirn.example.org:443 \
	-servername openirn.example.org </dev/null 2>/dev/null |
	openssl x509 -noout -subject -issuer -dates
```

Planifier le renouvellement avant expiration et tester le rechargement Apache.

# 4. Contrôle mensuel

- réaliser une restauration complète dans une base vide ;
- examiner les comptes actifs et leurs rôles ;
- révoquer les sessions inutiles ;
- examiner les terminaux inactifs ou inconnus ;
- contrôler les événements de sécurité et limitations répétées ;
- vérifier les releases et dépendances disponibles ;
- tester la mise à jour sur une instance ou un groupe pilote ;
- vérifier que la documentation PDF publiée correspond à la version utilisée.

# 5. Sauvegardes

## Sauvegarde planifiée

Le timer exécute une sauvegarde quotidienne à l'heure définie dans `openirn-api-backup.timer`. Contrôler son prochain passage :

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

Identifier les fichiers récents :

```bash
find /var/lib/openirn-api/backups -maxdepth 1 -type f \
	-newermt '15 minutes ago' -printf '%f %s octets\n' | sort
```

Le manifeste HMAC détecte une modification accidentelle ou malveillante des fichiers, mais ne chiffre pas les données. Chiffrer les copies hors site et limiter leur accès.

## Rétention

`OPENIRN_API_BACKUP_KEEP` fixe le nombre de sauvegardes conservées localement. Ne pas réduire la rétention avant d'avoir confirmé les copies externes. Une suppression de sauvegarde est irréversible si aucune autre copie n'existe.

# 6. Exercice de restauration

La restauration officielle cible une **base vide distincte**. L'outil refuse par défaut la base source et une cible non vide.

## Préparer une cible de test

Choisir un nom daté, puis ouvrir MariaDB sans historique :

```bash
MYSQL_HISTFILE=/dev/null mariadb
```

Adapter les valeurs :

```sql
CREATE DATABASE openirn_restore_YYYYMMDD
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'openirn_restore'@'localhost'
  IDENTIFIED BY 'MOT_DE_PASSE_À_REMPLACER';
GRANT ALL PRIVILEGES ON openirn_restore_YYYYMMDD.*
  TO 'openirn_restore'@'localhost';
FLUSH PRIVILEGES;
```

Créer un fichier temporaire protégé :

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

Examiner le rapport : migrations, nombres de lignes, clés étrangères et catégories d'orphelins doivent être valides.

## Détruire la cible de test

Les commandes suivantes suppriment définitivement la base restaurée et son compte. Ne les exécuter qu'après validation du rapport et de la cible exacte :

```bash
MYSQL_HISTFILE=/dev/null mariadb
```

```sql
DROP DATABASE openirn_restore_YYYYMMDD;
DROP USER 'openirn_restore'@'localhost';
```

Puis supprimer le fichier de connexion temporaire :

```bash
rm /etc/openirn-api-restore.env
```

# 7. Reprise après perte de la base active

Une restauration réelle est une opération de crise :

1. arrêter l'API pour stopper les écritures ;
2. conserver la base défaillante sans la modifier ;
3. restaurer dans une nouvelle base vide ;
4. valider le rapport de restauration ;
5. modifier l'URL runtime vers la nouvelle base ;
6. démarrer l'API ;
7. exécuter les contrôles interne et public ;
8. réaliser une recette fonctionnelle ;
9. ne supprimer l'ancienne base qu'après décision formelle et expiration du délai de retour arrière.

Ne jamais restaurer directement par-dessus une base active ou partiellement remplie.

# 8. Mise à jour du serveur API

## Préparer

1. lire les notes de release ;
2. vérifier la compatibilité client/API ;
3. contrôler l'espace disque ;
4. réaliser et externaliser une sauvegarde ;
5. annoncer la fenêtre de maintenance ;
6. conserver le chemin de la version actuellement active.

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
	"$release_dir/app/version.py" \
	"$release_dir/app/main.py" \
	"$release_dir/tools/"*.py
```

## Migrer et basculer

L'arrêt interrompt les utilisateurs et les synchronisations. Vérifier la fenêtre de maintenance avant cette commande :

```bash
systemctl stop openirn-api
```

Appliquer les migrations avec le code de la nouvelle version :

```bash
cd "$release_dir"
set -a
. /etc/openirn-api.env
. /etc/openirn-api-migration.env
set +a
.venv/bin/python tools/migrate_mariadb.py
unset OPENIRN_MIGRATION_MYSQL_URL OPENIRN_API_MYSQL_URL
```

La commande suivante remplace le lien symbolique actif. Le retour au code précédent restera possible, mais une migration de données peut ne pas être réversible, la sauvegarde est donc obligatoire :

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

Puis vérifier avec un terminal pilote :

- choix de l'espace ;
- ouverture et verrouillage de session ;
- référentiel ;
- campagne de recette ;
- écriture autorisée ;
- synchronisation sur un second terminal ;
- synthèse et export ;
- administration selon le rôle.

# 9. Retour arrière du code

Si la nouvelle version échoue avant toute migration irréversible, repointer le lien vers la version précédente :

```bash
systemctl stop openirn-api
ln -sfn /opt/openirn-releases/vVERSION_PRÉCÉDENTE /opt/openirn-api
systemctl start openirn-api
systemctl is-active openirn-api
```

Si le schéma ou les données ont changé, ne pas démarrer aveuglément l'ancien code. Restaurer la sauvegarde dans une nouvelle base, la valider puis basculer l'URL runtime conformément au plan de reprise.

# 10. Mise à jour des applications

1. vérifier les empreintes de la release ;
2. déployer Android et Windows sur un groupe pilote ;
3. mettre à jour en place, sans désinstallation ;
4. vérifier que l'enrôlement a été conservé ;
5. tester les rôles représentatifs ;
6. surveiller l'API et le journal sécurité ;
7. élargir la vague.

Les releases actuelles ne publient pas d'artefacts Apple signés.

# 11. Dépannage par symptôme

## API inactive

```bash
systemctl status openirn-api --no-pager
journalctl -u openirn-api -n 150 --no-pager
```

Vérifier ensuite :

```bash
readlink -f /opt/openirn-api
stat -c '%U %G %a %n' /etc/openirn-api.env
cd /opt/openirn-api
.venv/bin/python -m py_compile app/version.py app/main.py app/database_contract.py
```

Causes courantes : dépendance absente, URL MariaDB incorrecte, migration manquante, privilèges runtime trop larges ou fichier d'environnement absent.

## Health interne OK, public en 502

```bash
apache2ctl configtest
systemctl status apache2 --no-pager
tail -n 150 /var/log/apache2/openirn-api-error.log
curl --verbose http://127.0.0.1:8091/health
```

Vérifier `ProxyPass`, le chemin `/api/`, le certificat et les règles réseau locales.

## Réponse 413

Une réponse `413` signifie que le corps dépasse une limite. Les valeurs par défaut sont 1 Mio pour une requête ordinaire, 16 Mio pour la synchronisation et 5 Mio pour un import XLSX, avec 64 Mio décompressés au maximum.

Ne pas relever globalement la limite sans identifier la route et le besoin. Vérifier aussi `LimitRequestBody` côté Apache.

## Réponse 429

Une réponse `429` sur l'enrôlement indique une limitation anti-abus. Attendre la durée `Retry-After`, vérifier l'adresse client remontée par le proxy et rechercher une répétition anormale dans le journal sécurité.

## Terminal non autorisé ou 403

Vérifier dans cet ordre :

1. espace sélectionné ;
2. présence du terminal dans cet espace ;
3. statut actif et absence de révocation ;
4. session utilisateur valide ;
5. rôle compatible avec l'action ;
6. heure du terminal et du serveur.

Un terminal autorisé dans un espace ne l'est pas automatiquement dans les autres.

## Session expirée

Demander à l'utilisateur de revenir à l'accueil et de se déverrouiller. Si le problème se répète immédiatement :

```bash
timedatectl status
journalctl -u openirn-api --since '15 minutes ago' --no-pager
```

Vérifier les paramètres `OPENIRN_SESSION_TTL_MINUTES` et `OPENIRN_SESSION_IDLE_TIMEOUT_MINUTES` sans afficher le reste du fichier d'environnement.

## Sauvegarde en échec

```bash
systemctl status openirn-api-backup.service --no-pager
journalctl -u openirn-api-backup.service -n 150 --no-pager
namei -l /var/lib/openirn-api/backups
df -h /var/lib/openirn-api
```

Vérifier le binaire de dump, les droits `www-data`, l'espace disque et la présence d'un secret de signature d'au moins 32 caractères.

## Synchronisation incohérente

- suspendre les modifications concurrentes sur la campagne concernée ;
- noter la campagne, l'espace, les terminaux et l'heure ;
- consulter **Administration → Historique / conflits** ;
- comparer la révision courante et les révisions précédentes ;
- ne restaurer une révision qu'après avoir compris les données perdues par ce choix.

La restauration de campagne crée une nouvelle évolution serveur, elle ne remplace pas une restauration MariaDB globale.

# 12. Administration de sécurité dans l'application

## Utilisateurs

- désactiver rapidement les comptes sortants ;
- vérifier périodiquement les administrateurs et Pilotes IRN ;
- attribuer un PIN temporaire non trivial uniquement lorsque nécessaire ;
- confirmer que le changement est exigé à la prochaine connexion ;
- utiliser des comptes nominatifs.

## Sessions

Dans **Administration → Sessions serveur**, révoquer les sessions inconnues, anciennes ou associées à un incident. Une réinitialisation de PIN par un administrateur révoque les sessions existantes de l'utilisateur ciblé.

## Terminaux

- vérifier nom, plateforme, espace et dernière activité ;
- approuver une demande seulement après confirmation du demandeur ;
- révoquer immédiatement un terminal perdu ;
- supprimer les autorisations devenues inutiles ;
- conserver le terminal dans le seul périmètre nécessaire.

## Journal sécurité

Rechercher les échecs répétés, limitations, créations de codes, enrôlements, révocations, changements de PIN, changements de rôles et remplacements du répertoire utilisateurs. Le journal ne doit contenir ni identifiant métier brut, ni adresse source brute, ni PIN, ni jeton, ni code d'enrôlement, ni nom ou adresse électronique. Une opération transactionnelle absente du journal peut avoir été annulée par MariaDB ; la contrôler dans les erreurs de l'API avant de conclure à une lacune d'audit.

# 13. Gestion des espaces de travail

Chaque espace isole utilisateurs, campagnes, inventaire et autorisations de terminal. Le référentiel officiel est global et partagé.

Lors de la création d'un espace :

1. choisir un nom métier non ambigu ;
2. désigner un Pilote IRN initial ;
3. vérifier ses coordonnées et son rôle ;
4. enrôler explicitement les terminaux nécessaires ;
5. créer ou importer l'inventaire ;
6. réaliser une campagne de recette.

La suppression d'un espace est destructive et peut supprimer ses données rattachées. Exporter ce qui doit être conservé, réaliser une sauvegarde vérifiée et confirmer l'identifiant exact avant l'action.

# 14. Référentiel officiel

L'administrateur utilise **Administration → Référentiel officiel aDRI** pour :

- vérifier la version distante ;
- examiner les métadonnées et le rapport de validation ;
- importer la version courante ;
- consulter l'historique.

Avant une mise à jour, sauvegarder l'instance et tester la version sur une campagne de recette.

# 15. Capacité et nettoyage

Surveiller :

```bash
df -h
du -sh /var/lib/openirn-api /var/lib/openirn-api/backups /opt/openirn-releases/*
journalctl --disk-usage
```

Ne pas supprimer directement des lignes MariaDB ni des fichiers de sauvegarde sans passer par une procédure approuvée. Pour les anciennes versions API, conserver au minimum la version active et la version de retour arrière validée. Vérifier qu'aucun processus n'utilise une version avant de la retirer.

# 16. Fiche d'incident

Collecter sans secret :

- date, heure et fuseau ;
- espace concerné ;
- rôle de l'utilisateur ;
- plateforme et version de l'application ;
- action exacte ;
- code HTTP et message visible ;
- état des services ;
- extraits de journaux limités à la fenêtre de l'incident ;
- dernière sauvegarde connue ;
- changements récents de serveur ou d'application.

Ne pas collecter le code PIN, le code d'enrôlement, l'en-tête `Authorization`, un fichier `.env`, une clé privée ou un dump complet dans un ticket.

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
- [ ] connexion et changement d'espace testés ;
- [ ] lecture et écriture de recette testées ;
- [ ] synchronisation multi-terminal testée ;
- [ ] sauvegarde post-changement créée ;
- [ ] résultat et limites consignés sans secret.
