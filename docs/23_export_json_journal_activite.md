# Patch 021 — Export JSON enrichi avec le journal d’activité

Ce patch enrichit l’export JSON de campagne locale en y ajoutant le journal d’activité.

## Objectif

L’export ne contient plus uniquement les réponses et les scores. Il embarque aussi la trace locale des actions ayant conduit à l’état courant de la campagne.

## Nouveau contenu exporté

Le JSON passe en `schemaVersion: 4` et ajoute un bloc :

```json
{
  "activityLog": {
    "included": true,
    "eventCount": 3,
    "retentionPolicy": "local_last_300_events_per_campaign",
    "events": []
  }
}
```

Chaque évènement contient notamment :

- `id` ;
- `type` ;
- `typeLabel` ;
- `title` ;
- `description` ;
- `criterionId` si applicable ;
- `fromValue` / `toValue` si applicable ;
- `createdAt`.

## Limite assumée

Le journal reste local et limité aux 300 derniers évènements par campagne. Le futur audit trail serveur sera plus strict : utilisateur, appareil, horodatage serveur, signature éventuelle et politique de rétention dédiée.
