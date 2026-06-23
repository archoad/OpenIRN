# OpenIRN — correction du nom projet Flutter

Flutter déduit le nom du package depuis le dossier courant si `--project-name` n'est pas fourni. Comme le dossier technique s'appelle `flutter/`, il faut forcer le package Dart à `openirn`.

Le nom technique du package est :

```yaml
name: openirn
```

Le nom affiché de l'application est :

```text
OpenIRN
```

Après application du patch, lancer :

```bash
./tools/repair_flutter_project.sh
```

Ce script supprime le test par défaut `test/widget_test.dart`, qui pointe vers `MyApp`, puis normalise les imports Dart vers `package:openirn/...`.
