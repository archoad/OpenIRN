# Patch 011 — Vue radar des 8 piliers IRN

Ce patch ajoute une première visualisation graphique de la synthèse IRN.

## Objectif

L’écran `Synthèse IRN` affiche désormais :

- le score global officiel ;
- la lecture rapide ;
- un radar des 8 piliers ;
- la liste des scores par pilier ;
- la répartition par portée ;
- les points forts et points d’attention provisoires.

Le radar utilise la règle de scoring déjà en place :

```text
score = R / (R + NR) × 100
```

Les critères `N.C.` restent exclus du score, mais ils restent visibles via la complétude.

## Fichiers ajoutés

```text
flutter/lib/presentation/assessment/widgets/pillar_radar_chart.dart
```

## Fichiers modifiés

```text
flutter/lib/presentation/assessment/assessment_summary_screen.dart
```

## Design technique

La vue radar est implémentée avec un `CustomPainter`, sans dépendance graphique externe.

Cela évite d’ajouter une dépendance prématurée comme `fl_chart` ou équivalent. Si le besoin évolue vers des dashboards plus riches, on pourra remplacer ce composant par une librairie de charting plus complète.

## Utilisation

Depuis la racine du projet :

```bash
unzip -o irn_starter_kit_patch_011.zip
cd flutter
flutter clean
flutter pub get
flutter test
flutter run -d macos
```

Ensuite :

1. ouvrir l’évaluation R / NR ;
2. coter quelques critères ;
3. cliquer sur `Synthèse` ;
4. consulter le radar des 8 piliers.
