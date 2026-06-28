# Patch 119 — Icône application OpenIRN

Ce patch intègre l’icône OpenIRN retenue comme icône native de l’application.

## Fichiers mis à jour

- Android : `flutter/android/app/src/main/res/mipmap-*/ic_launcher.png`
- iOS : `flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png`
- macOS : `flutter/macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png`
- Windows : `flutter/windows/runner/resources/app_icon.ico`

## Fichiers source ajoutés

- `flutter/assets/branding/openirn_app_icon.png`
- `flutter/assets/branding/openirn_app_icon_source.png`
- `flutter/assets/branding/openirn_logo.svg`

## Après application

Il est recommandé d’exécuter :

```bash
cd ~/Desktop/OpenIRN/flutter
flutter clean
flutter pub get
flutter analyze
flutter run
```

Sur iOS/macOS, si l’ancienne icône reste affichée à cause du cache système, supprimer l’application du simulateur ou de l’appareil, puis relancer une installation propre.
