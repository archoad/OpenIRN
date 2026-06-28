# Patch 117 — Correctif lints underscores

Ce patch corrige les nouveaux avertissements remontés par `flutter analyze` après la mise à jour des lints Flutter.

## Correction

Les callbacks `separatorBuilder` qui utilisaient `(_, __)` utilisent maintenant `(_, _)`, conformément à la règle `unnecessary_underscores`.

## Fichiers modifiés

- `flutter/lib/presentation/campaigns/campaign_list_screen.dart`
- `flutter/lib/presentation/referential/referential_overview_screen.dart`
- `flutter/lib/presentation/sync/sync_log_screen.dart`
- `flutter/lib/presentation/users/user_list_screen.dart`

## Validation

```bash
cd ~/Desktop/OpenIRN/flutter
flutter analyze
```
