# Patch 123A-e — Correctif macOS Keychain sans sandbox

## Objectif

Le patch 123A a déplacé le jeton terminal vers `flutter_secure_storage`.
Sur macOS, l'accès au Keychain échouait avec l'erreur `-34018` quand l'application était sandboxée sans entitlement Keychain.
Le correctif 123A-c/123A-d ajoutait un entitlement Keychain, mais cela obligeait Xcode à signer l'application avec un certificat de développement, ce qui bloquait `flutter run -d macos`.

Ce patch adopte une configuration de développement plus simple pour OpenIRN :

- suppression de l'entitlement `keychain-access-groups` ;
- suppression de l'App Sandbox macOS dans les entitlements Flutter ;
- l'application macOS locale peut compiler sans certificat de développement ;
- `flutter_secure_storage` peut utiliser le Keychain utilisateur hors sandbox.

## Fichiers modifiés

- `flutter/macos/Runner/DebugProfile.entitlements`
- `flutter/macos/Runner/Release.entitlements`

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

Pour une distribution macOS signée/notarisée ou une distribution App Store, il faudra réintroduire une configuration de signature/capabilities propre dans Xcode.
Pour le développement local et la distribution directe hors App Store, cette configuration évite la dépendance à un certificat de développement tout en permettant l'utilisation du Keychain utilisateur.
