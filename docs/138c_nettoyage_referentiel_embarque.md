# 138C — Nettoyage du référentiel embarqué obsolète

Ce patch poursuit la phase de sanitization post-`v0.5.0` en supprimant les derniers reliquats du mode **référentiel Flutter embarqué**.

Depuis le patch `123B`, OpenIRN fonctionne en mode **référentiel serveur uniquement** :

- le référentiel officiel est installé depuis l’écran d’administration ;
- l’API expose le référentiel actif aux terminaux autorisés ;
- l’historique des installations est conservé côté serveur ;
- les sauvegardes serveur protègent la base et les fichiers de référentiel.

Le dépôt n’a donc plus besoin d’embarquer un ancien JSON runtime dans l’application Flutter.

## Fichiers supprimés par le script

```text
flutter/assets/referentials/adri_irn_v1_1.json
flutter/assets/referentials/manifest.json
flutter/assets/referentials/
flutter/pubspec_fragment.yaml
server/scripts/build_referential_bundle.py
```

## Fichiers conservés

Les scripts suivants restent utiles côté serveur et sont conservés :

```text
server/scripts/import_adri_referential.py
server/scripts/validate_adri_referential.py
```

Ils servent toujours à produire ou vérifier un JSON canonique avant installation via le serveur, mais ils ne produisent plus de bundle Flutter.

## Garde-fous ajoutés

`tools/check_open_source_readiness.sh` signale désormais une erreur si le dépôt contient à nouveau :

- `flutter/assets/referentials/` ;
- `flutter/pubspec_fragment.yaml` ;
- `server/scripts/build_referential_bundle.py` ;
- une déclaration `assets/referentials` dans `flutter/pubspec.yaml`.

`.gitignore` ignore aussi les anciens chemins de bundle local pour éviter leur réintroduction accidentelle.

## Documentation historique

Les documents anciens `docs/05_*`, `docs/06_*` et `docs/34_*` sont conservés comme journal de conception, mais reçoivent une note d’obsolescence. Ils ne décrivent plus l’architecture active.

## Application

Depuis la racine du dépôt :

```bash
unzip -o ~/Downloads/openirn_patch_138c_nettoyage_referentiel_embarque.zip
chmod +x tools/apply_openirn_patch_138c_embedded_referential_cleanup.sh
./tools/apply_openirn_patch_138c_embedded_referential_cleanup.sh
```

## Vérifications recommandées

```bash
./tools/check_open_source_readiness.sh
cd flutter
flutter analyze
flutter test
```

Puis :

```bash
git status --short
git diff --stat
```
