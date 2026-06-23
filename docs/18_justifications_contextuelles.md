# Patch 016 — Justifications contextuelles

Ce patch ajuste l'écran d'évaluation R / NR.

## Comportement

- Le bouton **Ajouter une justification** n'apparaît plus pour un critère en `N.C.`.
- Le bloc de justification n'apparaît que lorsque le critère est coté `R` ou `NR`.
- Si un critère déjà justifié est repassé en `N.C.`, sa justification est vidée afin d'éviter une justification masquée mais toujours exportée.

## Fichier modifié

- `flutter/lib/presentation/assessment/assessment_screen.dart`

## Vérification

```bash
cd flutter
flutter clean
flutter pub get
flutter test
flutter run -d macos
```
