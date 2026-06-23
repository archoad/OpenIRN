# Mapping de l'Excel interne vers le modèle applicatif

Fichier source analysé : `Evaluation IRN.xlsx`.

## Onglets identifiés

| Onglet | Usage | Cible applicative |
|---|---|---|
| Méthodo | Processus de travail | Documentation / assistant de campagne |
| 1-Desc Stack | Cartographie Entité → Fonction métier → Système → Fonction technique → Asset | Cartography |
| 2- Table Assets | Harmonisation des assets | HarmonizedAsset |
| 3- Assignation Evaluation | Assignation des critères aux évaluateurs | Assignment |
| 4- Evaluation Assets | Notes et justificatifs | Evaluation |
| Référentiels | Référentiel interne initial | À remplacer par l'import aDRI officiel |

## Colonnes principales

### `1-Desc Stack`

| Colonne Excel | Champ JSON |
|---|---|
| Ref. ent | entity.id |
| Entité (Ent) | entity.name |
| Ref. FM | businessFunction.id |
| Fonction Métier (FM) | businessFunction.name |
| Ref. Sys | criticalSystem.id |
| Système (Sys) | criticalSystem.name |
| Ref. FT | technicalFunction.id |
| Fonction Technique (FT) | technicalFunction.name |
| Ref. As | asset.id |
| Asset (As) | asset.name |

### `2- Table Assets`

| Colonne Excel | Champ JSON |
|---|---|
| Ref. FT | technicalFunctionId |
| Fonction Technique (FT) | technicalFunctionName |
| Ref. As | sourceAssetId |
| Asset (As) | sourceAssetName |
| Asset Commun | isCommon |
| Ref. Ash | harmonizedAssetId |
| Asset Homogénéisé (ASH) | harmonizedAssetName |

### `3- Assignation Evaluation`

| Colonne Excel | Champ JSON |
|---|---|
| Ref. Ash | targetId |
| Asset Homogénéisé (ASH) | targetName |
| Entité évaluatrice | evaluatorEntityId |
| Critères Fonc. ou Org. | organizationEvaluator |
| RES-x.y | criterion assignment |

### `4- Evaluation Assets`

Cet onglet est plus proche d'une grille de saisie que d'une table normalisée. Il doit être converti en lignes :

```text
campaignId, targetId, criterionId, officialAnswer, internalMaturityLevel, internalScore, justification
```

## Contrôles qualité à appliquer

- Chaque asset doit avoir un identifiant stable.
- Un asset commun doit avoir une référence harmonisée.
- Chaque critère utilisé dans les assignations doit exister dans le référentiel aDRI actif.
- Une évaluation validée doit être immutable sauf réouverture explicite.
- Les lignes `N.C.` doivent être exclues des moyennes de score.

