# Patch 122b — Correctif analyse Flutter

Ce correctif corrige une chaîne Dart non échappée dans `referential_overview_screen.dart`.

## Correction

La chaîne :

```dart
subtitle: 'Créer ou ouvrir une campagne d'évaluation',
```

est remplacée par une chaîne entre guillemets doubles :

```dart
subtitle: "Créer ou ouvrir une campagne d'évaluation",
```

Cela corrige les erreurs `expected_token`, `illegal_character`, `unterminated_string_literal` et `undefined_identifier` remontées par `flutter analyze`.
