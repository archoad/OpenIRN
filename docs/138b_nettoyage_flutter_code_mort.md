# 138B — Nettoyage du code Flutter mort

Ce patch poursuit la phase de sanitization post-`v0.5.0` en supprimant les reliquats Flutter identifiés comme non atteignables depuis l'application actuelle.

## Objectif

Réduire la surface de maintenance sans modifier le comportement fonctionnel actuel de l'application.

Le patch ne touche pas aux écrans actifs de campagnes, d'évaluation, d'administration, de référentiel officiel, de sessions, d'audit ou de maintenance serveur.

## Fichiers supprimés par le script

```text
flutter/lib/presentation/sync/sync_screen.dart
flutter/lib/presentation/sync/sync_log_screen.dart
flutter/lib/presentation/assessment/assessment_import_screen.dart
flutter/lib/domain/services/assessment_import_service.dart
flutter/test/assessment_import_service_test.dart
flutter/lib/domain/models/campaign.dart
flutter/lib/domain/models/evaluation.dart
flutter/lib/domain/services/scoring_service.dart
flutter/lib/domain/models/cartography.dart
flutter/lib/data/sync/sync_operation.dart
flutter/lib/data/repositories/asset_irn_referential_repository.dart
flutter/lib/presentation/referential/referential_provider.dart
```

## Pourquoi ces suppressions ?

### Ancienne synchronisation manuelle

Les anciens écrans `sync_screen.dart` et `sync_log_screen.dart` ne sont plus appelés depuis `main.dart` ni depuis les écrans actifs. Ils ont été remplacés par les mécanismes serveur, session et synchronisation plus récents.

### Ancien import local d'évaluation

`assessment_import_screen.dart` et `assessment_import_service.dart` correspondent à l'ancien flux d'import local. L'application actuelle s'appuie sur les campagnes serveur et les mécanismes de restauration/synchronisation sécurisés.

Le test associé `assessment_import_service_test.dart` est supprimé avec le service qu'il couvrait.

### Modèles et services historiques

Les fichiers `campaign.dart`, `evaluation.dart`, `scoring_service.dart`, `cartography.dart` et `sync_operation.dart` ne sont plus importés par le code actif. Les modèles actifs sont désormais notamment `local_campaign.dart`, `irn_assessment.dart`, `official_referential.dart` et les services de scoring officiel.

### Ancien référentiel embarqué

`asset_irn_referential_repository.dart` et `referential_provider.dart` ne sont plus utilisés par l'application actuelle, qui démarre sur `ReferentialOverviewScreen` avec `ApiIrnReferentialRepository`.

La suppression complète des assets de référentiel embarqué est volontairement reportée au patch 138C.

## Application

Depuis la racine du dépôt :

```bash
unzip -o ~/Downloads/openirn_patch_138b_nettoyage_flutter_code_mort.zip
chmod +x tools/apply_openirn_patch_138b_flutter_dead_code.sh
./tools/apply_openirn_patch_138b_flutter_dead_code.sh
```

## Vérifications recommandées

```bash
cd flutter
flutter analyze
flutter test
```

Puis :

```bash
git status --short
git diff --stat
```

## Notes

Le script vérifie qu'aucun import direct vers les fichiers supprimés ne subsiste dans `flutter/lib` ou `flutter/test`.
