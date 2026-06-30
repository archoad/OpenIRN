# Patch 133 — Matrice centralisée des permissions

Ce patch centralise les droits applicatifs dans `AccessPolicyService`.

## Objectif

Supprimer progressivement les tests de rôles dispersés dans les écrans Flutter et les remplacer par une matrice explicite de permissions.

## Permissions principales

- consultation du référentiel ;
- ouverture des campagnes ;
- synthèse et qualité ;
- saisie des critères affectés ;
- gestion de campagne ;
- gestion des affectations ;
- export JSON ;
- journal de campagne ;
- administration ;
- utilisateurs ;
- terminaux autorisés ;
- journal sécurité ;
- sessions serveur ;
- référentiel officiel ;
- historique / conflits ;
- maintenance serveur.

## Matrice cible

### Administrateur

Accès complet : campagnes, utilisateurs, terminaux, sécurité, sessions, référentiel officiel, historique et maintenance serveur.

### Pilote IRN

Accès au pilotage métier : campagnes, affectations, saisie complète, export, journal de campagne et historique / conflits.

Le Pilote IRN peut ouvrir la page Administration, mais seules les opérations autorisées par la matrice y sont affichées.

### Évaluateur

Accès aux campagnes, synthèse, qualité, et saisie uniquement des critères qui lui sont affectés.

### Validateur

Accès aux campagnes, synthèse et qualité. Il ne modifie pas les réponses.

### Lecteur

Accès en lecture : campagnes, synthèse et qualité.

## Fichiers principaux

- `flutter/lib/domain/services/access_policy_service.dart`
- `flutter/lib/presentation/admin/administration_screen.dart`
- `flutter/lib/presentation/referential/referential_overview_screen.dart`
- `flutter/lib/presentation/campaigns/campaign_list_screen.dart`
- `flutter/lib/presentation/assessment/assessment_screen.dart`
- `flutter/test/access_policy_service_test.dart`
