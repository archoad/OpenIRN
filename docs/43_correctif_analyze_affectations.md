# Correctif analyze — affectations évaluateurs

Ce correctif supprime un opérateur null-aware inutile dans l’écran d’affectation des critères.

Dans `_assignCriterion`, `selectedUser` est contrôlé avant usage :

```dart
final selectedUser = state.userById(userId);
if (selectedUser == null) {
  return;
}
```

Après ce garde, Dart sait que `selectedUser` ne peut plus être null. L’accès doit donc être direct :

```dart
toValue: selectedUser.displayName,
```

Cela corrige le warning `invalid_null_aware_operator` remonté par `flutter analyze`.
