# Patch 123A-f — Correctif runtime Keychain macOS

## Objectif

Le patch 123A a déplacé la configuration de synchronisation vers `flutter_secure_storage`.
Sur macOS, certains builds locaux non signés peuvent toujours déclencher l'erreur Keychain `-34018` :

```text
PlatformException(Unexpected security result code, Code: -34018, Message: A required entitlement isn't present.)
```

Même après avoir retiré les entitlements bloquants, le plugin natif peut continuer à refuser l'accès au Keychain dans ce contexte de développement.

## Correction

Le dépôt `LocalSyncConfigurationRepository` devient plus robuste :

- il utilise toujours `flutter_secure_storage` par défaut ;
- si macOS retourne l'erreur `-34018`, il bascule automatiquement sur le Keychain utilisateur via l'outil système `/usr/bin/security` ;
- si le Keychain reste indisponible, un fallback local évite le crash pour ne pas bloquer l'application ;
- les erreurs de stockage sécurisé ne remontent plus en exception non gérée pendant le rafraîchissement automatique.

## Fichier modifié

- `flutter/lib/data/repositories/local_sync_configuration_repository.dart`

## Validation

```bash
cd ~/Desktop/OpenIRN/flutter
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

## Note sécurité

Sur iOS, Android, Windows et Linux, le stockage sécurisé natif reste le chemin nominal.
Sur macOS, le chemin nominal reste `flutter_secure_storage`, mais le patch ajoute un contournement dédié aux builds locaux non signés pour éviter l'erreur `-34018`.
Pour une distribution macOS signée/notarisée, il faudra stabiliser les entitlements et la signature dans Xcode.
