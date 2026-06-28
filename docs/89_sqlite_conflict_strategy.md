# Patch 089 — Proposition SQLite et gestion des conflits

Ce patch est volontairement non intrusif : il pose le schéma SQLite, la stratégie de migration et les règles de conflit avant de remplacer le backend JSON.

## Objectif

Remplacer le stockage actuel sous `/var/lib/openirn-api` :

```text
sync-push/<tenant>/<device>/<serverSyncId>.json
users/<tenant>/users.json
users/<tenant>/credentials.json
```

par une base SQLite unique :

```text
/var/lib/openirn-api/openirn.sqlite3
```

Le JSON reste utilisé comme format d'échange API, mais il n'est plus le format de persistance principal.

## Tables proposées

- `tenants` : tenants OpenIRN.
- `users` : base utilisateurs centrale.
- `user_credentials` : codes utilisateurs hachés PBKDF2-SHA256.
- `sync_snapshots` : snapshots reçus, pour audit et compatibilité `/sync/pull`.
- `campaign_states` : dernière version serveur par campagne.
- `campaign_revisions` : historique complet des versions de campagne.
- `sync_events` : journal serveur, utilisé par SSE et audit.

## Stratégie de conflit v1

La v1 doit rester simple et robuste :

```text
serveur = source de vérité
campagne = unité de conflit
politique = last write wins contrôlé
historique = conservé dans campaign_revisions
```

Quand un terminal pousse une campagne :

1. Le serveur calcule le hash canonique de la campagne.
2. Il compare avec `campaign_states`.
3. Si la campagne n'existe pas : création `server_revision = 1`.
4. Si le contenu est identique : pas de nouvelle révision.
5. Si le contenu diffère : nouvelle révision `server_revision + 1`.
6. Si une autre machine a publié entre-temps : `conflict_detected = 1` dans `campaign_revisions`.
7. La version reçue devient la version courante selon `last_write_wins`.
8. Les anciennes versions restent restaurables côté serveur.

Cette règle colle au comportement actuel de l'application : les terminaux convergent automatiquement vers la dernière version serveur.

## Évolution v2 recommandée

Une fois SQLite en place, ajouter côté client :

```json
{
  "sync": {
    "tenantId": "archoad",
    "deviceId": "...",
    "baseServerSyncId": "...",
    "baseCampaignRevisions": {
      "campaign-id": 12
    }
  }
}
```

Le serveur pourra alors distinguer :

- mise à jour normale ;
- push basé sur une version obsolète ;
- conflit réel ;
- fusion possible au niveau critère.

## Pourquoi SQLite maintenant ?

SQLite est suffisant pour le niveau actuel d'OpenIRN :

- installation simple ;
- zéro service supplémentaire ;
- transactions ACID ;
- WAL pour lectures concurrentes ;
- migration facile vers PostgreSQL plus tard.

## Plan de migration recommandé

### Étape 1 — Patch 089

Ajouter le schéma SQL et l'outil de migration JSON → SQLite.

### Étape 2 — Patch 090

Modifier FastAPI pour lire/écrire dans SQLite tout en conservant les mêmes endpoints :

```text
GET  /users
POST /users/replace
POST /users/pin
POST /auth/verify
POST /sync/push
GET  /sync/status
GET  /sync/pull
GET  /sync/events
```

Aucun changement client obligatoire.

### Étape 3 — Patch 091

Ajouter les métadonnées de version côté client et enrichir les messages de conflit.

### Étape 4 — Patch 092

Ajouter une page admin “Historique serveur” avec restauration d'une version de campagne.
