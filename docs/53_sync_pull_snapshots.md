# Patch 058 — Récupération des snapshots serveur `/sync/pull`

Ce patch ajoute la première brique de **pull serveur** dans OpenIRN.

## Objectif

Après `POST /sync/push`, le client peut maintenant interroger :

```http
GET /api/sync/pull?tenantId=archoad&limit=10
Authorization: Bearer <token>
```

Le serveur retourne les derniers snapshots stockés pour le tenant configuré.

## Important

Cette étape est volontairement prudente : les snapshots distants sont **récupérés et affichés pour inspection**, mais ils ne sont pas encore appliqués localement.

L'application locale n'est donc pas modifiée par le pull.

## Côté serveur

Le backend FastAPI ajoute :

```text
GET /sync/pull
```

Il lit les fichiers stockés dans :

```text
/var/lib/openirn-api/sync-push/<tenant>/<device>/sync_*.json
```

et retourne les plus récents.

## Côté client Flutter

L'écran `Synchronisation` ajoute une carte :

```text
Snapshots distants /sync/pull
```

avec un bouton :

```text
Récupérer
```

## Suite prévue

La prochaine étape consistera à ajouter une action explicite :

```text
Importer ce snapshot distant
```

avec confirmation utilisateur, contrôle du référentiel, gestion des doublons de campagne et journalisation locale.
