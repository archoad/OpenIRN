> **Note v0.5.0 / patch 138C** : ce document décrit l’ancienne application référentiel locale. Le chargement `assets/referentials` est retiré ; l’application utilise désormais le référentiel officiel exposé par l’API.

# Lot 004 — Première application Flutter référentiel

## Objectif

Ce lot transforme le socle référentiel en une première application Flutter exécutable.

Périmètre :

- chargement du manifeste `assets/referentials/manifest.json` ;
- chargement du référentiel actif ;
- affichage de la version, licence, source et checksum ;
- affichage des 8 piliers ;
- affichage des critères par pilier ;
- recherche simple par code, pilier, intitulé ou description ;
- fiche détail d'un critère.

Le lot ne traite toujours pas les données entreprise : pas d'asset, pas de campagne, pas d'utilisateur, pas d'API.

## Préparer le dossier Flutter

Depuis la racine du starter kit :

```bash
cd flutter
flutter create --platforms=windows,android,ios .
cd ..
```

Puis appliquer le patch 004 :

```bash
unzip -o irn_starter_kit_patch_004.zip
```

## Préparer le bundle référentiel

Depuis la racine du starter kit :

```bash
python server/scripts/build_referential_bundle.py \
  --input canonical_irn_v1_1.json \
  --output-dir flutter/assets/referentials
```

Les fichiers attendus sont :

```text
flutter/assets/referentials/adri_irn_v1_1.json
flutter/assets/referentials/manifest.json
```

## Lancer l'application

```bash
cd flutter
flutter pub get
flutter run -d macos
```

ou, pour Windows depuis une machine Windows :

```bash
flutter run -d windows
```

Pour afficher les devices disponibles :

```bash
flutter devices
```

## Tests

```bash
cd flutter
flutter test
```

## Résultat attendu

L'application doit afficher :

- le titre `IRN — Référentiel officiel` ;
- la version `v1.1` ;
- `8 piliers` ;
- `30 critères` ;
- une répartition par portée : organisation / actif numérique ;
- les critères regroupés par pilier ;
- une fiche détail à l'ouverture d'un critère.
