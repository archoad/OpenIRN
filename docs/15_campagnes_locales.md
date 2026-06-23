# Patch 013 — Campagnes locales

Ce lot introduit le premier concept de campagne dans OpenIRN, sans serveur et sans données entreprise.

## Objectif

Avant ce patch, l'évaluation R / NR était unique pour un référentiel donné. Désormais, les réponses sont rattachées à une campagne locale.

Cela prépare :

- les campagnes serveur ;
- le multi-utilisateur ;
- la synchronisation API ;
- l'import ultérieur des données entreprise ;
- la comparaison entre plusieurs évaluations.

## Nouveau modèle

```text
LocalCampaign
├── id
├── referentialId
├── name
├── description
├── createdAt
└── updatedAt
```

## Stockage local

Les campagnes locales sont stockées dans `shared_preferences` :

```text
openirn.localCampaigns.<referentialId>
```

Les réponses sont maintenant isolées par campagne :

```text
openirn.assessment.answers.<referentialId>.<campaignId>
```

Une compatibilité est conservée avec l'ancien usage sans campagne via l'identifiant interne `default`.

## Parcours utilisateur

```text
Référentiel officiel
 → Campagnes locales
 → Ouvrir une campagne
 → Évaluation R / NR
 → Synthèse
 → Export JSON
```

## Limites assumées

Ce patch utilise encore `shared_preferences`. C'est suffisant pour valider le modèle fonctionnel, mais la persistance devra migrer vers SQLite/Drift lors de l'ajout de la synchronisation API.
