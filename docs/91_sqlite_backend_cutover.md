# Patch 091 — Bascule du backend OpenIRN API vers SQLite

Ce patch remplace le stockage principal JSON par SQLite pour les endpoints API existants.

## Objectif

Le format JSON reste le format d'échange entre l'application Flutter et l'API, mais le serveur stocke maintenant les données dans :

```text
/var/lib/openirn-api/openirn.sqlite3
```

Les anciens fichiers JSON peuvent être conservés comme archive ou sauvegarde, mais ne sont plus utilisés par `main.py` après déploiement du patch.

## Endpoints inchangés

Le client Flutter continue d'utiliser les mêmes endpoints :

```text
GET  /health
POST /auth/verify
GET  /users
POST /users/replace
POST /users/pin
POST /sync/push
GET  /sync/status
GET  /sync/pull
GET  /sync/events
```

## Modèle de conflit

La stratégie appliquée est :

```text
unité de conflit : campagne
politique         : last_write_wins
source de vérité  : serveur SQLite
historique        : conservé dans campaign_revisions
```

Quand une campagne déjà connue reçoit une nouvelle version :

1. le serveur crée une nouvelle entrée dans `campaign_revisions` ;
2. il incrémente `server_revision` ;
3. il remplace `campaign_states` par la dernière version reçue ;
4. si la version précédente venait d'un autre `device_id`, le conflit est journalisé ;
5. SSE notifie les terminaux connectés via `/sync/events`.

## Tables principales

```text
sync_snapshots      historique brut des snapshots reçus
campaign_states     dernière version serveur de chaque campagne
campaign_revisions  historique versionné des campagnes
sync_events         journal serveur
users               base utilisateurs centrale
user_credentials    codes utilisateurs hachés PBKDF2-SHA256
```

## Rollback

Le patch ne supprime pas les anciens JSON. En cas de problème, remettre l'ancien `main.py` et redémarrer le service.
