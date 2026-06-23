# Correctif export/import fichier JSON

Ce correctif rend les actions fichier plus explicites :

- message visible quand le dialogue système doit s’ouvrir ;
- indicateur de chargement pendant l’ouverture/enregistrement ;
- erreurs affichées dans l’interface ;
- écriture desktop via `dart:io` pour éviter les échecs silencieux ;
- script d’ajout des entitlements macOS nécessaires aux fichiers sélectionnés par l’utilisateur.

## macOS

Après application du patch, exécuter :

```bash
chmod +x tools/enable_macos_file_dialog_entitlements.sh
./tools/enable_macos_file_dialog_entitlements.sh
```

Puis reconstruire :

```bash
cd flutter
flutter clean
flutter pub get
flutter test
flutter run -d macos
```

Les entitlements ajoutés sont :

```xml
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

Ils permettent à l’application sandboxée macOS de lire/écrire les fichiers choisis explicitement par l’utilisateur.
