# Patch 123E — Journal de synchronisation en mémoire uniquement

OpenIRN poursuit la migration server-only.

## Objectif

Le journal de synchronisation ne doit plus être stocké localement dans `SharedPreferences`.
Il devient un journal d'état en mémoire, valable uniquement pendant l'exécution de l'application.

## Changements

- `LocalSyncLogRepository` ne persiste plus les événements dans `SharedPreferences`.
- L'ancienne clé `openirn.sync.log.events` est purgée automatiquement.
- Les événements récents restent disponibles en mémoire pour éviter de retraiter le même snapshot durant la session en cours.
- Les tests sont adaptés à ce fonctionnement non persistant.

## Données locales restantes

Après ce patch, le stockage local métier continue de disparaître progressivement.
Les seules données conservées localement restent les métadonnées non sensibles nécessaires à l'enrôlement : `tenantId`, `deviceId` et la configuration publique de connexion.
