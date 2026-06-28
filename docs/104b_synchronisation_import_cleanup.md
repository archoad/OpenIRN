# Patch 104b — Nettoyage import synchronisation globale

Ce correctif supprime l'import inutile `package:flutter/foundation.dart` dans `AppSyncCoordinator`.

Il corrige l'avertissement `unnecessary_import` remonté par `flutter analyze` après le patch 104.

Fichier modifié :

- `flutter/lib/domain/services/app_sync_coordinator.dart`
