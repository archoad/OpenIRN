# Patch 123A-d — Correctif Keychain macOS sans signature développeur

## Objectif

Le patch 123A-c ajoutait un groupe Keychain explicite :

```xml
<string>$(AppIdentifierPrefix)$(CFBundleIdentifier)</string>
```

Sur macOS, ce groupe explicite peut imposer une signature avec certificat de développement et bloquer `flutter run -d macos`.

Ce correctif remplace ce groupe explicite par la configuration recommandée pour `flutter_secure_storage` :

```xml
<key>keychain-access-groups</key>
<array/>
```

## Fichiers modifiés

- `flutter/macos/Runner/DebugProfile.entitlements`
- `flutter/macos/Runner/Release.entitlements`

## Validation

```bash
cd ~/Desktop/OpenIRN/flutter
flutter clean
flutter pub get
flutter analyze
flutter run -d macos
```

## Note

Si le projet est ensuite signé/notarisé pour distribution macOS, une configuration de signature explicite pourra être remise en place dans Xcode avec un Team ID valide.
