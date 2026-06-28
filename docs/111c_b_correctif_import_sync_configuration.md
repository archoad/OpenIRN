# Patch 111C-b — Correctif import SyncConfiguration

## Objet

Ce correctif complète le patch 111C en ajoutant l'import manquant du modèle `SyncConfiguration` dans l'écran d'accueil.

## Fichier modifié

- `flutter/lib/presentation/referential/referential_overview_screen.dart`

## Correction

Ajout de :

```dart
import '../../domain/models/sync_configuration.dart';
```

Cela corrige les erreurs `non_type_as_type_argument` remontées par `flutter analyze` sur `Future<SyncConfiguration>` et `FutureBuilder<SyncConfiguration>`.
