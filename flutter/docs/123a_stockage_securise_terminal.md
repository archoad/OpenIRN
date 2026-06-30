# Patch 123A — Stockage sécurisé du terminal

Objectif : sortir la configuration sensible du terminal du stockage `SharedPreferences`.

## Changements

- Ajout de la dépendance `flutter_secure_storage`.
- Déplacement de la configuration de synchronisation vers le stockage sécurisé de la plateforme.
- Migration automatique au premier lancement depuis les anciennes clés :
  - `openirn.sync.configuration`
  - `openirn.sync.deviceId`
- Suppression automatique des anciennes clés `SharedPreferences` après migration.
- Conservation de l'API existante `LocalSyncConfigurationRepository` afin de ne pas impacter les écrans existants.

## Données désormais stockées dans le stockage sécurisé

- `tenantId`
- `deviceId`
- `apiToken` / jeton terminal
- état d'activation de la synchronisation
- date de mise à jour

## Données volontairement non traitées dans ce patch

Ce patch ne supprime pas encore les anciennes données métier locales : utilisateurs, campagnes, réponses, affectations, journal d'activité, journal de synchronisation. Elles seront traitées dans les patchs suivants de la série 123.

## Vérification

```bash
cd flutter
flutter clean
flutter pub get
flutter analyze
flutter run
```

Au premier lancement après le patch, un terminal déjà appairé doit rester appairé. Le jeton est migré automatiquement puis retiré de `SharedPreferences`.
