# Patch 094 — Restauration d’une révision serveur

Ce patch ajoute la possibilité de restaurer une révision précédente d’une campagne depuis l’écran administrateur `Historique / conflits`.

## Objectif

Lorsqu’un conflit `last_write_wins` a écrasé une version utile, un administrateur ou un pilote IRN peut sélectionner une révision antérieure et la replacer comme version courante.

## Principe

La restauration ne modifie pas l’historique existant :

- la révision source reste intacte ;
- une nouvelle révision serveur est créée ;
- `campaign_states` pointe vers cette nouvelle révision ;
- un snapshot synthétique est inséré dans `sync_snapshots` ;
- les clients connectés sont notifiés via SSE ;
- les terminaux convergent automatiquement vers la version restaurée.

## Endpoint ajouté

`POST /campaigns/restore`

Payload :

```json
{
  "tenantId": "archoad",
  "campaignId": "local-adri-irn-v1-1-...",
  "serverRevision": 12,
  "restoredByUserId": "user-id",
  "reason": "restore_from_openirn_admin_ui"
}
```

## Interface OpenIRN

Dans `Historique / conflits`, chaque révision affiche maintenant :

- `Payload` pour consulter le JSON ;
- `Restaurer` pour remettre cette révision comme version courante.
