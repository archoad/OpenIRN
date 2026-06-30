# Patch 123A-c — Correctif entitlements Keychain macOS

## Objectif

Corriger l'erreur suivante après l'introduction de `flutter_secure_storage` :

```text
PlatformException(Unexpected security result code, Code: -34018, Message: A required entitlement isn't present.)
```

Cette erreur apparaît lorsque l'application macOS tente d'écrire dans le Keychain sans entitlement de groupe d'accès Keychain.

## Modification

Ajout de l'entitlement suivant dans :

- `flutter/macos/Runner/DebugProfile.entitlements`
- `flutter/macos/Runner/Release.entitlements`

```xml
<key>keychain-access-groups</key>
<array>
	<string>$(AppIdentifierPrefix)$(CFBundleIdentifier)</string>
</array>
```

## Après application

Effectuer un nettoyage complet avant de relancer l'application macOS :

```bash
cd ~/Desktop/OpenIRN/flutter
flutter clean
flutter pub get
flutter analyze
flutter run -d macos
```

Si l'ancienne application était déjà installée/lancée, la fermer complètement avant de relancer.
