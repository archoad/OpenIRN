# Patch 123C-b — Correctif analyse utilisateurs serveur uniquement

Ce correctif supprime un import devenu inutile dans `local_user_repository.dart` après la migration vers les utilisateurs serveur uniquement.

## Fichier modifié

- `flutter/lib/data/repositories/local_user_repository.dart`

## Correction

Suppression de l'import inutilisé :

```dart
import '../../domain/models/sync_configuration.dart';
```

## Validation

```bash
cd ~/Desktop/OpenIRN/flutter
flutter analyze
flutter test
```
