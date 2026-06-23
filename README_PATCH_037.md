# Patch 037 — référentiel officiel embarqué dans les assets Flutter

Ce patch versionne directement le bundle JSON du référentiel officiel aDRI dans les assets Flutter.

## Changements principaux

- Ajout de `flutter/assets/referentials/adri_irn_v1_1.json`.
- Ajout de `flutter/assets/referentials/manifest.json`.
- Suppression des règles `.gitignore` qui excluaient les JSON du référentiel embarqué.
- Suppression attendue de `flutter/assets/referentials/.gitkeep`.
- Mise à jour du contrôle `tools/check_open_source_readiness.sh`.
- Mise à jour du README, du NOTICE et des notes de release GitHub.

## Application

```bash
unzip -o irn_starter_kit_patch_037.zip
chmod +x tools/apply_patch_037_embed_referential_assets.sh
./tools/apply_patch_037_embed_referential_assets.sh
./tools/check_open_source_readiness.sh
cd flutter
flutter clean
flutter pub get
flutter analyze
flutter test
```

## Publication

Après commit/push, créer une nouvelle release :

```bash
git tag v0.1.1
git push origin v0.1.1
```

Le build Windows doit alors embarquer :

```text
data/flutter_assets/assets/referentials/manifest.json
data/flutter_assets/assets/referentials/adri_irn_v1_1.json
```
