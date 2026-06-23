# OpenIRN — Workflow de statut des campagnes locales

Ce lot ajoute un premier workflow local de campagne.

## Statuts disponibles

| Statut | Usage |
|---|---|
| `draft` | Campagne en brouillon, modifiable. |
| `ready_for_review` | Campagne complète et prête pour revue. |
| `validated` | Campagne validée, affichée en lecture seule. |
| `archived` | Campagne archivée, affichée en lecture seule. |

## Règle de passage en revue

Une campagne ne peut être marquée `ready_for_review` que si le contrôle qualité est complet :

1. tous les critères actifs sont cotés `R` ou `NR` ;
2. toutes les réponses `R` ou `NR` ont une justification.

## Lecture seule

Les statuts `validated` et `archived` rendent l'écran d'évaluation non modifiable :

- les choix `N.C. / R / NR` sont désactivés ;
- les justifications ne peuvent plus être modifiées ;
- la réinitialisation est désactivée.

Le mode local permet encore de rouvrir une campagne en brouillon. Cette souplesse sera à revoir lorsque le workflow serveur et les rôles utilisateurs seront ajoutés.

## Export JSON

L'export JSON passe en `schemaVersion: 3` et inclut désormais le statut de campagne :

```json
{
  "campaign": {
    "id": "local-default-adri-irn-v1-1",
    "name": "Évaluation locale — IRN v1.1",
    "status": "ready_for_review",
    "statusLabel": "Prêt pour revue",
    "statusUpdatedAt": "2026-06-22T14:00:00.000Z"
  }
}
```
