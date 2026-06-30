# Patch 123F — Purge des anciennes données locales métier

Ce patch finalise le nettoyage côté client après la migration server-only.

## Objectif

L'application ne doit plus conserver de données métier locales historiques issues du mode local-first.

Le client conserve uniquement les métadonnées publiques nécessaires à l'appairage du terminal :

- `openirn.sync.configuration` ;
- `openirn.sync.deviceId`.

Ces données ne contiennent plus de bearer ni de jeton terminal persistant.

## Données purgées au démarrage

Le service `LegacyLocalStoragePurgeService` supprime automatiquement les anciennes clés :

- `openirn.localUsers` ;
- `openirn.localSession.activeUserId` ;
- `openirn.sync.log.events` ;
- `openirn.localCampaigns.*` ;
- `openirn.assessment.answers.*` ;
- `openirn.criterionAssignments.*` ;
- `openirn.activityLog.*` ;
- anciens reliquats `openirn.secure.*` et `openirn.secureFallback.*`.

## Effet attendu

Après le premier démarrage suivant le patch, le stockage local ne contient plus de référentiel, d'utilisateurs, de campagnes, de réponses, de justifications, d'affectations ni de journaux métier.

Le serveur reste la source de vérité unique.
