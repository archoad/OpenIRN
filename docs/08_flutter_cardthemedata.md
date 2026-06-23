# Patch 006 — Compatibilité ThemeData.cardTheme

Les versions récentes de Flutter attendent `CardThemeData` dans `ThemeData.cardTheme`.

Erreur corrigée :

```text
The argument type 'CardTheme' can't be assigned to the parameter type 'CardThemeData?'
```

Correction :

```dart
cardTheme: CardThemeData(
  clipBehavior: Clip.antiAlias,
  elevation: 0,
  shape: RoundedRectangleBorder(...),
),
```

Ce patch renomme également la classe principale en `OpenIrnApp` et le titre applicatif en `OpenIRN`.
