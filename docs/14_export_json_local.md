# Patch 012 — Export JSON local

Ce patch ajoute un export JSON de l’évaluation R / NR locale.

## Objectif

L’application sait maintenant produire un payload JSON complet contenant :

- la traçabilité du référentiel officiel aDRI ;
- la version et le checksum du référentiel ;
- les réponses `R`, `NR` et `N.C.` ;
- le score global ;
- les scores par pilier ;
- les scores par portée ;
- les métadonnées d’export.

Cet export prépare le futur contrat de synchronisation API, sans introduire encore de serveur ni de modèle multi-utilisateurs.

## Fichiers ajoutés

```text
flutter/lib/domain/services/assessment_export_service.dart
flutter/lib/presentation/assessment/assessment_export_screen.dart
flutter/test/assessment_export_service_test.dart
```

## Fichier modifié

```text
flutter/lib/presentation/assessment/assessment_summary_screen.dart
```

## Utilisation

Depuis l’application :

1. ouvrir `Évaluation R / NR` ;
2. renseigner quelques critères ;
3. ouvrir `Synthèse` ;
4. cliquer sur `Export JSON` ;
5. copier le JSON dans le presse-papiers.

## Commandes

```bash
unzip -o irn_starter_kit_patch_012.zip
cd flutter
flutter clean
flutter pub get
flutter test
flutter run -d macos
```

## Remarque

Pour l’instant, l’export copie le JSON dans le presse-papiers. Cela évite d’ajouter tout de suite une dépendance de sélection de fichier ou de partage système. Un vrai export fichier multiplateforme sera ajouté plus tard, au moment de stabiliser les campagnes et la synchronisation API.
