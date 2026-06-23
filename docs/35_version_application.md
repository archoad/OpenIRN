# Version applicative dans OpenIRN

Le patch 038 ajoute l’affichage de la version applicative dans l’écran **À propos**.

La version affichée est lue depuis les métadonnées natives générées à partir de `flutter/pubspec.yaml` grâce au package `package_info_plus`.

## Fichiers modifiés

- `flutter/pubspec.yaml`
- `flutter/lib/presentation/about/about_screen.dart`

## Version courante

Le fichier `pubspec.yaml` passe à :

```yaml
version: 0.1.1+2
```

La convention utilisée est :

```text
version sémantique + numéro de build
```

Exemple :

```text
OpenIRN 0.1.1+2
```

## Vérification

```bash
cd flutter
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

Puis ouvrir :

```text
À propos
```

L’écran doit afficher un chip du type :

```text
OpenIRN 0.1.1+2
```

## Notes de version

Avant chaque nouvelle release, penser à mettre à jour :

- `flutter/pubspec.yaml` ;
- le tag Git, par exemple `v0.1.2` ;
- les notes de release GitHub.
