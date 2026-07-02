# Patch 140C — Correctif `tilePadding`

## Objectif

Corriger une régression introduite par le patch 140B : une référence à `tilePadding` a été propagée par erreur dans `_ScoreLineCard`, alors que cette variable locale n'existe que dans `_IndicatorTile`.

## Correction

Dans `flutter/lib/presentation/assessment/assessment_summary_screen.dart`, le padding de `_ScoreLineCard` redevient constant :

```dart
padding: const EdgeInsets.all(14),
```

Le padding adaptatif reste conservé uniquement dans les tuiles des indicateurs IRN.
