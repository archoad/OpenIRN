> **Note v0.5.0 / patch 138C** : cette décision est historique et n’est plus l’architecture active. Le bundle `flutter/assets/referentials` et son générateur ont été supprimés pendant la sanitization post-v0.5.0.

# Référentiel officiel embarqué dans les assets Flutter

À partir du patch 037, OpenIRN versionne directement le bundle JSON du référentiel officiel aDRI dans :

```text
flutter/assets/referentials/adri_irn_v1_1.json
flutter/assets/referentials/manifest.json
```

## Pourquoi ce choix ?

Ce choix rend les builds plus simples et plus robustes :

- les builds locaux et GitHub Actions utilisent exactement le même référentiel ;
- les artefacts Windows, macOS, Android et iOS embarquent le référentiel sans étape de génération ;
- l’application ne dépend pas d’un téléchargement GitLab pendant la CI ;
- le message “Impossible de charger le référentiel” ne doit plus apparaître dans les builds publiés.

## Ce qui reste exclu du dépôt

Les fichiers de travail restent exclus :

```text
Questionnaire_IRN_*.xlsx
Questionnaire_IRN_*.ods
canonical_irn_*.json
validation_referential_report.json
```

Le dépôt versionne uniquement le bundle runtime nécessaire à Flutter, avec les métadonnées d’attribution : source, version, licence, chemin du fichier source et checksum.

## Mise à jour future du référentiel

Pour mettre à jour le bundle lors d’une nouvelle version officielle :

```bash
curl -L \
  -o Questionnaire_IRN_v.X.Y.xlsx \
  "<url officielle aDRI>"

python server/scripts/import_adri_referential.py \
  --input Questionnaire_IRN_v.X.Y.xlsx \
  --output canonical_irn_vX_Y.json \
  --version vX.Y

python server/scripts/validate_adri_referential.py \
  --input canonical_irn_vX_Y.json \
  --output validation_referential_report.json

python server/scripts/build_referential_bundle.py \
  --input canonical_irn_vX_Y.json \
  --output-dir flutter/assets/referentials
```

Puis vérifier :

```bash
./tools/check_open_source_readiness.sh
cd flutter
flutter analyze
flutter test
```

## Nettoyage

Le fichier `.gitkeep` n’est plus nécessaire dans `flutter/assets/referentials/`, car le dossier contient désormais les deux JSON versionnés.
