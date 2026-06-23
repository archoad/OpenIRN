# Patch 032 — Nettoyage `flutter analyze`

Ce patch nettoie les remarques `info` remontées par `flutter analyze` après les premiers lots OpenIRN.

Il corrige notamment :

- l'import inutile de `dart:typed_data` ;
- quelques déclarations `final` remplacées par `const` ;
- des constructeurs pouvant être marqués `const` ;
- les suggestions automatiques restantes via `dart fix --apply`.

## Application

Depuis la racine du projet :

```bash
unzip -o irn_starter_kit_patch_032.zip
chmod +x tools/fix_flutter_analyze_infos.sh
./tools/fix_flutter_analyze_infos.sh
```

Puis :

```bash
cd flutter
flutter analyze
flutter test
flutter run -d macos
```
