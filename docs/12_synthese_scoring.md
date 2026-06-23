# Patch 010 — Synthèse de scoring IRN

Ce patch ajoute un premier tableau de bord de scoring, toujours limité au référentiel officiel aDRI et à l’évaluation locale R / NR.

## Objectif

L’application sait déjà :

- charger le référentiel officiel ;
- afficher les piliers et critères ;
- saisir des réponses `N.C.`, `R`, `NR` ;
- persister ces réponses localement.

Ce patch ajoute une synthèse lisible :

- score global officiel ;
- complétude ;
- score par pilier ;
- score par portée ;
- points forts provisoires ;
- points d’attention provisoires.

## Règle de score

Pour l’instant, la règle reste volontairement simple :

```text
score = R / (R + NR) × 100
```

Les critères `N.C.` sont exclus du score, mais comptent dans la complétude.

## Utilisation

Depuis l’écran `Évaluation R / NR`, cliquer sur le bouton `Synthèse` dans la barre supérieure.

## Fichiers ajoutés ou modifiés

```text
flutter/lib/domain/services/official_rnr_scoring_service.dart
flutter/lib/presentation/assessment/assessment_screen.dart
flutter/lib/presentation/assessment/assessment_summary_screen.dart
flutter/test/official_rnr_scoring_service_test.dart
```

## Commandes

```bash
cd flutter
flutter test
flutter run -d macos
```
