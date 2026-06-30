# GitHub Actions CI

Cette documentation décrit les contrôles CI de qualité et de publication du dépôt OpenIRN.

## Workflows

### Flutter CI

Fichier :

```text
.github/workflows/flutter_ci.yml
```

Le workflow s’exécute à chaque push et pull request vers `main` ou `master`.

Il lance :

```bash
cd flutter
flutter pub get
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
```

### Open source readiness

Fichier :

```text
.github/workflows/open_source_readiness.yml
```

Ce workflow lance :

```bash
./tools/check_open_source_readiness.sh
```

Son rôle est d’éviter la publication accidentelle de fichiers temporaires, de métadonnées OS, de fichiers de travail référentiel, d’exports de campagnes, de données internes ou de secrets.

## Dependabot

Fichier :

```text
.github/dependabot.yml
```

Dependabot vérifie chaque semaine les mises à jour de :

- GitHub Actions ;
- dépendances Flutter/Dart dans `flutter/pubspec.yaml`.

## Notes

La CI ne remplace pas la relecture manuelle de `git status` avant publication. Elle sert de filet de sécurité pour les erreurs récurrentes : `.DS_Store`, swaps d’éditeur, `.tmp/`, fichiers de travail ou secrets.
