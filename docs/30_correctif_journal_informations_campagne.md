# Patch 028 — Correctif journal d’activité

Le patch 027 a ajouté le type d’évènement `campaignInformationUpdated` pour tracer les modifications des informations de campagne.

L’écran du journal d’activité utilisait un `switch` exhaustif sur `LocalActivityType`, mais ne gérait pas encore ce nouveau type. Le build Flutter échouait donc avec :

```text
The type 'LocalActivityType' is not exhaustively matched by the switch cases since it doesn't match 'LocalActivityType.campaignInformationUpdated'.
```

Ce patch ajoute le cas manquant dans `activity_log_screen.dart`.

## Fichier modifié

```text
flutter/lib/presentation/activity/activity_log_screen.dart
```

## Vérification

```bash
cd flutter
flutter clean
flutter pub get
flutter test
flutter run -d macos
```
