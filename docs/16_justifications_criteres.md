# Patch 014 — Justifications par critère

Ce lot ajoute une justification locale par critère dans les campagnes OpenIRN.

## Objectif

Une réponse `R`, `NR` ou `N.C.` devient exploitable uniquement si elle est documentée. Le patch ajoute donc un champ libre de justification sur chaque critère du référentiel officiel.

## Comportement utilisateur

Dans l'écran d'évaluation :

- chaque critère conserve les choix `N.C.`, `R`, `NR` ;
- un bouton permet d'ajouter ou modifier une justification ;
- la justification est sauvegardée localement avec la campagne ;
- l'écran affiche le nombre de justifications renseignées ;
- l'export JSON inclut le champ `justification` pour chaque critère.

## Persistance locale

Le stockage local passe au schéma `schemaVersion: 2`.

Ancien format :

```json
{
  "answers": {
    "RES-1.1": "resilient"
  }
}
```

Nouveau format :

```json
{
  "schemaVersion": 2,
  "referentialId": "adri-irn-v1.1",
  "campaignId": "local-default-adri-irn-v1-1",
  "answers": {
    "RES-1.1": {
      "answer": "resilient",
      "justification": "La gouvernance est documentée et revue annuellement."
    }
  }
}
```

Le lecteur reste compatible avec l'ancien format.

## Export JSON

L'export passe également en `schemaVersion: 2` et ajoute :

```json
{
  "criterionId": "RES-1.1",
  "answer": "R",
  "justification": "...",
  "hasJustification": true
}
```

## Limite volontaire

Les justifications restent des champs texte simples. Les preuves, pièces jointes, statuts de validation et commentaires de relecture seront ajoutés plus tard, au moment du workflow multi-utilisateurs.
