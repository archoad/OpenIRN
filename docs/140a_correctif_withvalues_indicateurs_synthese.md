# Patch 140A — Correctif analyse Flutter `withValues`

## Objectif

Corriger les avertissements `deprecated_member_use` remontés par `flutter analyze` après le patch 140.

Le patch remplace les appels `Color.withOpacity(...)` introduits dans le bloc **Indicateurs IRN** par la forme recommandée par Flutter :

```dart
withValues(alpha: 0.xx)
```

## Fichier modifié

- `flutter/lib/presentation/assessment/assessment_summary_screen.dart`

## Impact fonctionnel

Aucun changement fonctionnel ou visuel attendu. Le rendu reste identique ; seule l’API Flutter utilisée change.
