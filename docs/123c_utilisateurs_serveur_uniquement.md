# Patch 123C — Utilisateurs serveur uniquement

Ce patch poursuit la migration d’OpenIRN vers un fonctionnement **server-only**.

## Objectif

Supprimer les derniers comportements hérités du prototype local-first pour la gestion des utilisateurs :

- plus de création automatique d’un administrateur local ;
- plus de cache local `openirn.localUsers` ;
- plus de session utilisateur persistée dans `openirn.localSession.activeUserId` ;
- plus de bascule vers une base utilisateurs locale de secours ;
- lecture des utilisateurs uniquement depuis l’API OpenIRN ;
- modifications utilisateurs uniquement via l’API OpenIRN ;
- utilisateur actif conservé uniquement en mémoire pendant la session serveur courte.

## Changements Flutter

Fichiers modifiés :

- `flutter/lib/domain/services/app_session_manager.dart`
- `flutter/lib/data/repositories/local_user_repository.dart`
- `flutter/lib/data/repositories/local_session_repository.dart`
- `flutter/lib/data/api/openirn_api_client.dart`
- `flutter/lib/presentation/users/user_list_screen.dart`
- `flutter/lib/presentation/campaigns/campaign_list_screen.dart`
- `flutter/lib/presentation/referential/referential_overview_screen.dart`
- `flutter/test/local_user_repository_test.dart`
- `flutter/test/local_session_repository_test.dart`

## Comportement attendu

Un terminal autorisé peut lire la base utilisateurs depuis le serveur.

Une action protégée doit ouvrir une session serveur courte via :

```text
POST /auth/verify
```

La session reçue est conservée uniquement en mémoire par `AppSessionManager`.

Si l’application est fermée, la session disparaît. Au prochain lancement, l’utilisateur doit de nouveau sélectionner son profil et saisir son code personnel.

## Données locales supprimées

Le patch purge automatiquement :

```text
openirn.localUsers
```

La session locale historique n’est plus utilisée. Le repository correspondant ne lit plus ni n’écrit plus `SharedPreferences`.

## Validation

```bash
cd ~/Desktop/OpenIRN/flutter
flutter analyze
flutter test
flutter run -d macos
```
