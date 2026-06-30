# Patch 123D-b — Correctif import inutilisé

Ce patch corrige le warning `flutter analyze` apparu après le passage des campagnes en mode serveur uniquement.

## Correction

Suppression de l'import inutilisé :

```dart
import '../models/local_campaign.dart';
```

dans :

```text
flutter/lib/domain/services/sync_automation_service.dart
```

Aucun changement fonctionnel.
