# Patch 008 — Piliers repliés par défaut

Ce patch modifie l'écran principal du référentiel OpenIRN.

## Comportement

- Au chargement initial, seuls les 8 piliers sont visibles.
- Les critères restent repliés par défaut.
- Lorsqu'une recherche est saisie, les piliers contenant des résultats se déplient automatiquement.
- Si la recherche est effacée, les piliers reviennent à l'état replié au prochain rendu.

## Fichier modifié

```text
flutter/lib/presentation/referential/referential_overview_screen.dart
```

## Vérification

```bash
cd flutter
flutter test
flutter run -d macos
```
