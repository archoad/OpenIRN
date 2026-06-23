# Modèle de synchronisation offline-first

## Principe

L'application Flutter sauvegarde toujours localement en premier. Chaque modification produit une opération dans une outbox locale. La synchronisation pousse ensuite les changements au serveur et récupère les modifications distantes.

```text
UI Flutter
  ↓
Repository
  ↓
SQLite local + JSON payload
  ↓
Sync outbox
  ↓
API serveur
```

## États de synchronisation

| État | Description |
|---|---|
| localOnly | Créé localement, pas encore synchronisé |
| pendingPush | En attente d'envoi |
| synced | Synchronisé |
| conflict | Conflit détecté |
| rejected | Rejeté par le serveur |

## Règles de conflit

| Cas | Règle |
|---|---|
| Évaluation en brouillon modifiée sur deux devices | Fusion champ par champ si possible |
| Évaluation soumise | Modification locale rejetée sauf réouverture |
| Évaluation validée | Lecture seule |
| Référentiel différent | Campagne incompatible, nouvelle campagne nécessaire |

## Outbox JSON

```json
{
  "id": "op-001",
  "entityType": "evaluation",
  "entityId": "eval-001",
  "operation": "upsert",
  "payload": {},
  "createdAt": "2026-06-22T14:00:00Z",
  "attempts": 0
}
```

