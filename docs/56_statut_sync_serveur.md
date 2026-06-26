# Patch 061 — Statut serveur de synchronisation

Ce patch ajoute un endpoint léger `GET /sync/status` côté API et une carte dédiée dans l'écran `Synchronisation API` côté Flutter.

## Objectif

Jusqu'ici, OpenIRN pouvait :

- pousser un snapshot complet avec `POST /sync/push` ;
- récupérer des snapshots complets avec `GET /sync/pull` ;
- importer explicitement un snapshot distant.

Le endpoint `GET /sync/status` permet maintenant de connaître l'état serveur sans télécharger les payloads complets.

## Endpoint ajouté

```http
GET /api/sync/status?tenantId=archoad
Authorization: Bearer <token>
```

Réponse type :

```json
{
  "status": "ok",
  "type": "openirn.syncStatus",
  "application": "OpenIRN API",
  "version": "0.5.0",
  "tenantId": "archoad",
  "serverTime": "2026-06-24T15:00:00Z",
  "snapshotCount": 3,
  "deviceCount": 2,
  "campaignCount": 5,
  "latestSnapshot": {
    "serverSyncId": "sync_20260624T150000Z_abcd1234ef56",
    "receivedAt": "2026-06-24T15:00:00Z",
    "tenantId": "archoad",
    "deviceId": "openirn-device-...",
    "payloadSha256": "...",
    "campaignCount": 2
  }
}
```

## Interface Flutter

Dans `Campagnes locales → Synchronisation`, une nouvelle carte apparaît :

```text
Statut serveur /sync/status
```

Elle affiche :

- le nombre de snapshots disponibles côté serveur ;
- le nombre d'appareils ayant poussé des données ;
- le nombre total de campagnes présentes dans les snapshots ;
- le dernier `serverSyncId` accepté ;
- l'appareil source du dernier snapshot.

## Déploiement serveur

Sur `srv` :

```bash
sudo cp server/openirn-api/app/main.py /opt/openirn-api/app/main.py
sudo systemctl restart openirn-api
sudo systemctl status openirn-api
```

Test manuel :

```bash
TOKEN='ton_token_api'

curl -s "https://www.archoad.io/api/sync/status?tenantId=archoad" \
  -H "Authorization: Bearer $TOKEN" | jq
```

## Intérêt pour la suite

Cette brique prépare :

- l'affichage du dernier état serveur ;
- la détection de snapshots plus récents ;
- le futur mécanisme de synchronisation différentielle ;
- la résolution de conflits sans télécharger tous les payloads dès l'ouverture de l'écran.
