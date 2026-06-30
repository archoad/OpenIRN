# Patch 123A-b — Correctif tests stockage sécurisé

## Objectif

Corriger les tests unitaires du repository de configuration de synchronisation après le passage au stockage sécurisé.

`flutter_secure_storage` utilise un plugin natif dans l'application réelle. Dans les tests Dart VM, il faut initialiser un stockage mocké, sinon les tests échouent avec :

```text
MissingPluginException(No implementation found for method read on channel plugins.it_nomads.com/flutter_secure_storage)
```

## Changement

Le test `local_sync_configuration_repository_test.dart` initialise maintenant :

```dart
FlutterSecureStorage.setMockInitialValues(<String, String>{});
```

à chaque `setUp`, en plus du mock `SharedPreferences` déjà présent.

## Fichiers modifiés

- `flutter/test/local_sync_configuration_repository_test.dart`
