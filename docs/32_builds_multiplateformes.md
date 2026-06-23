# Builds multiplateformes OpenIRN

Le workflow `.github/workflows/build_artifacts.yml` génère des artefacts OpenIRN pour plusieurs plateformes.

## Déclenchement

Le workflow est volontairement déclenché uniquement :

- manuellement via `workflow_dispatch` ;
- lors de la création d’un tag Git de type `v*`, par exemple `v0.1.0`.

Il ne s’exécute pas à chaque push pour éviter des builds longs et coûteux.

## Artefacts générés

| Plateforme | Job | Artefact |
|---|---|---|
| Android | `android-apk` | `openirn-android-apk` |
| macOS | `macos-app` | `openirn-macos` |
| Windows | `windows-app` | `openirn-windows` |
| iOS | `ios-no-codesign` | `openirn-ios-no-codesign` |

## Notes importantes

### Android

Le job produit un APK release non signé avec une clé de publication dédiée.
Pour publier sur Google Play, il faudra ajouter une configuration de signature via secrets GitHub.

### macOS

Le job produit un bundle `.app` compressé.
Pour distribuer publiquement l’application, il faudra ajouter signature, notarisation Apple et packaging `.dmg` ou `.pkg`.

### Windows

Le job produit une archive `.zip` contenant l’exécutable et les bibliothèques nécessaires.
Pour une distribution propre, on pourra ensuite ajouter un packaging MSIX ou Inno Setup.

### iOS

Le job exécute un build `--no-codesign`.
Il vérifie que le code compile pour iOS, mais ne produit pas une application installable sur appareil sans signature Apple.

## Commandes locales équivalentes

Depuis le dossier `flutter/` :

```bash
flutter build apk --release
flutter build macos --release
flutter build windows --release
flutter build ios --release --no-codesign
```

Les builds Windows doivent être lancés depuis Windows, et les builds iOS/macOS depuis macOS.

## Étape suivante possible

Une fois ces builds validés, on pourra ajouter un workflow de release qui attache automatiquement les artefacts à une release GitHub lors de la publication d’un tag.
