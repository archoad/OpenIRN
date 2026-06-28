# Patch 116 — Nettoyage des dépendances Flutter

## Objectif

Nettoyer les dépendances signalées comme obsolètes par `flutter analyze` / `flutter pub get`.

## Modifications

Fichier modifié :

- `flutter/pubspec.yaml`

Changements :

- suppression de `flutter_riverpod`, qui n'est pas utilisé dans le code actuel ;
- mise à jour de `package_info_plus` vers `^10.2.0` ;
- mise à jour de `flutter_lints` vers `^6.0.0` ;
- relèvement du SDK Dart minimal à `>=3.10.0` pour rester cohérent avec `package_info_plus 10.2.0`.

## Application

Depuis le projet :

```bash
cd ~/Desktop/OpenIRN
unzip -o ~/Downloads/patch_116_nettoyage_dependances_flutter_direct.zip
```

Puis :

```bash
cd ~/Desktop/OpenIRN/flutter
flutter clean
flutter pub upgrade --major-versions
flutter pub get
flutter analyze
```

## Note importante

Si `flutter pub get` indique que le SDK Dart local est trop ancien, mettre à jour Flutter :

```bash
flutter upgrade
flutter doctor
```

Certaines dépendances comme `matcher`, `meta`, `test_api` ou `vector_math` peuvent rester pilotées par la version du SDK Flutter et non par le `pubspec.yaml` de l'application.
