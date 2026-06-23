# Patch 022 — Correctif test export journal

Ce patch corrige le test `assessment_export_service_test.dart` introduit avec le patch 021.

## Problème

Le test construisait la liste `activityEvents` avec `const`, alors qu’un évènement contient :

```dart
createdAt: DateTime.utc(2026, 6, 22, 10)
```

`DateTime.utc(...)` n’est pas une expression constante en Dart. Le compilateur refuse donc la liste `const`.

## Correction

La liste devient simplement :

```dart
activityEvents: <LocalActivityEvent>[
```

Aucun code applicatif n’est modifié.
