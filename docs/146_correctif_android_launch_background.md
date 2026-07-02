# Patch 146 — Correctif Android `launch_background`

## Problème

La compilation GitHub Actions Android échouait pendant `flutter build apk --release` avec :

```text
Android resource linking failed
error: resource drawable/launch_background not found
```

Les thèmes Android `LaunchTheme` référencent toujours `@drawable/launch_background`, mais le fichier avait disparu du dossier Android après la génération/nettoyage des icônes.

## Correction

Le patch restaure :

- `flutter/android/app/src/main/res/drawable/launch_background.xml`
- `flutter/android/app/src/main/res/drawable-night/launch_background.xml`

Le premier fournit le fond clair de lancement Android, le second le fond nuit.

## Remarque

Ce patch ne modifie pas les icônes, le nom de package, le moteur Flutter, ni le code applicatif. Il rétablit uniquement la ressource Android attendue par `LaunchTheme`.
