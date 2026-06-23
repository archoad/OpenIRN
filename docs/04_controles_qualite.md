# Contrôles qualité IRN

Cette étape valide que le référentiel officiel aDRI et les données internes importées depuis Excel sont cohérents avant de commencer le développement Flutter.

## Commandes

```bash
python server/scripts/import_adri_referential.py \
  --input Questionnaire_IRN_v.1.1.xlsx \
  --output canonical_irn_v1_1.json \
  --version v1.1

python server/scripts/import_company_excel.py \
  --input "Evaluation IRN.xlsx" \
  --output company_seed.json \
  --campaign-id campaign-initial-import \
  --referential-id adri-irn-v1.1

python server/scripts/validate_irn_seed.py \
  --referential canonical_irn_v1_1.json \
  --company company_seed.json \
  --output validation_report.json
```

## Contrôles effectués

- 8 piliers dans le référentiel.
- Critères présents et identifiants uniques.
- Critères rattachés à un pilier existant.
- Entités, fonctions métier, systèmes, fonctions techniques et assets avec identifiants uniques.
- Liens hiérarchiques valides entre entités, fonctions, systèmes, fonctions techniques et assets.
- Assets harmonisés rattachés à des assets sources existants.
- Assignations rattachées à des critères existants.
- Assignations rattachées à des assets ou assets harmonisés existants.
- Détection des critères organisation/fonction assignés à des assets.
- Détection des critères organisation/fonction restant à traiter dans un écran dédié.

## Décision de conception associée

Les critères de portée `asset` alimentent directement les écrans d'évaluation asset.
Les critères de portée `organization` doivent être traités dans un module dédié : évaluation organisationnelle, fonction métier ou système critique selon le choix méthodologique retenu.
