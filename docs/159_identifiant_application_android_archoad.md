# Patch 159 — Identifiant Android Archoad

Ce patch remplace l’identifiant applicatif historique :

```text
io.github.myshelldubois.openirn
```

par l’identifiant cible :

```text
io.github.archoad.openirn
```

## Périmètre

Le changement couvre :

- l’`applicationId` Android ;
- le `namespace` Android ;
- le package Kotlin de `MainActivity` ;
- la variable `APP_BUNDLE_ID` du workflow GitHub Actions ;
- les identifiants iOS/macOS conservés pour cohérence future ;
- les métadonnées Windows de type `CompanyName`.

## Point d’attention Google Play

Ce changement doit être fait avant la première publication Google Play définitive avec l’ancien identifiant.

Si un bundle Android a déjà été associé à une application Play Console avec l’ancien package name, Google Play considérera le nouvel identifiant comme une autre application.

## Vérification locale

```bash
cd flutter
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
```

Le bundle généré doit porter l’identifiant :

```text
io.github.archoad.openirn
```
