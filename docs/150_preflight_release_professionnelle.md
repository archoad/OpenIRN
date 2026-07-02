# Patch 150 — Préflight release Android / Windows

## Objectif

Ce patch adapte le contrôle de pré-publication à la situation actuelle du projet :

- certificat Android fonctionnel ;
- certificat Windows auto-signé fonctionnel ;
- pas encore de compte Apple Developer payant.

Le profil de release courant produit donc uniquement les artefacts **Android** et **Windows** signés. macOS et iOS restent optionnels et seront ajoutés plus tard.

## Script principal

```bash
./tools/check_openirn_release_preflight.sh
```

Avec vérification du tag :

```bash
./tools/check_openirn_release_preflight.sh --tag v0.6.1
```

Avec vérification stricte des secrets Android / Windows présents dans l'environnement local :

```bash
./tools/check_openirn_release_preflight.sh --tag v0.6.1 --require-secrets
```

Contrôle Apple optionnel, pour plus tard :

```bash
./tools/check_openirn_release_preflight.sh --tag v0.6.1 --with-apple
```

## Ce qui est contrôlé

- cohérence du tag avec la version Flutter ;
- présence du numéro de build `+N` ;
- workflow GitHub Actions de release signé Android / Windows ;
- signature Android via `key.properties` ;
- signature Windows via `signtool` ;
- ressources Android de lancement ;
- absence des jobs macOS/iOS dans le profil courant ;
- protection des fichiers sensibles dans `.gitignore` ;
- absence de fichiers de signature suivis par Git.

## Workflow ajouté

```text
.github/workflows/release_preflight.yml
```

Il peut être lancé manuellement depuis GitHub Actions. Il ne publie rien.

## Usage recommandé

```bash
cd ~/Desktop/OpenIRN
./tools/check_openirn_release_preflight.sh --tag v0.6.1
cd flutter
flutter analyze
flutter test
flutter build apk --release
```

Puis :

```bash
git status
git add .
git commit -m "Prepare OpenIRN v0.6.1 release"
git tag v0.6.1
git push origin main
git push origin v0.6.1
```
