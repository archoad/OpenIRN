# Patch 092 — API d'administration des révisions et conflits

Ce patch ajoute des endpoints de consultation pour exploiter le stockage SQLite introduit au patch 091.

## Objectif

Permettre aux administrateurs de voir :

- les campagnes courantes côté serveur ;
- l'historique des révisions d'une campagne ;
- les conflits détectés ;
- le payload exact d'une révision donnée.

## Endpoints ajoutés

```http
GET /campaigns?tenantId=archoad
GET /campaigns/revisions?tenantId=archoad&campaignId=<ID>&limit=50
GET /campaigns/conflicts?tenantId=archoad&limit=50
GET /campaigns/conflicts?tenantId=archoad&campaignId=<ID>&limit=50
GET /campaigns/revision?tenantId=archoad&campaignId=<ID>&serverRevision=<N>
```

Tous ces endpoints nécessitent le bearer token API.

## Modèle de conflit

La politique reste `last_write_wins` :

- la dernière révision acceptée devient l'état courant dans `campaign_states` ;
- toutes les révisions sont conservées dans `campaign_revisions` ;
- une révision est marquée en conflit quand elle écrase une version issue d'un autre terminal ;
- l'état courant reste disponible, tandis que l'historique permet l'audit et une future restauration.

## Tests curl

```bash
TOKEN='ton_token_api'

curl -s 'https://www.archoad.io/api/campaigns?tenantId=archoad' \
  -H "Authorization: Bearer $TOKEN" | jq

curl -s 'https://www.archoad.io/api/campaigns/conflicts?tenantId=archoad&limit=20' \
  -H "Authorization: Bearer $TOKEN" | jq
```

Pour l'historique d'une campagne :

```bash
CID='local-adri-irn-v1-1-20260622160628030033'

curl -s "https://www.archoad.io/api/campaigns/revisions?tenantId=archoad&campaignId=$CID&limit=20" \
  -H "Authorization: Bearer $TOKEN" | jq
```
