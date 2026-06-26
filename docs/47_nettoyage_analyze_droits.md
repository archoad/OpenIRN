# Patch 049 — Nettoyage `flutter analyze` après droits de saisie

Ce patch nettoie les deux informations `prefer_const_constructors` ajoutées par le test `access_policy_service_test.dart`.

Il ne modifie pas le comportement applicatif.

## Validation

```bash
cd flutter
flutter analyze
flutter test
```
