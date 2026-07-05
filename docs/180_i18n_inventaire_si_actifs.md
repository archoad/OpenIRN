# Patch 180 — Internationalisation Inventaire SI / actifs

Ce patch poursuit la transition bilingue français / anglais d’OpenIRN.

## Périmètre migré

- Page **Fonctions critiques & actifs**.
- Cartouche de synthèse de l’inventaire IRN.
- Cartouches des fonctions critiques.
- Cartouches des systèmes d’information.
- Liste des actifs.
- Dialogues de création, modification et suppression :
  - fonction critique ;
  - système d’information ;
  - actif.
- Boutons d’import/export Excel par SI.
- Messages de confirmation d’import Excel.
- Libellés de criticité des actifs.

Les noms saisis par les utilisateurs restent inchangés : noms de fonctions critiques, SI, porteurs, actifs et descriptions.

## Fichiers modifiés

- `flutter/lib/presentation/admin/asset_inventory_management_screen.dart`
- `flutter/assets/i18n/fr.json`
- `flutter/assets/i18n/en.json`

## Validation recommandée

```bash
cd ~/Desktop/openIRN
unzip -o ~/Downloads/openirn_patch_180_i18n_inventaire_si_actifs_overlay.zip
cd flutter
flutter analyze
flutter test
```

