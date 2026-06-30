# Patch 130 — Audit et verrouillage du stockage local

## Objectif

OpenIRN 0.4.0 repose désormais sur une architecture **server-only** : le serveur est la source de vérité pour le référentiel, les utilisateurs, les campagnes, les réponses, les affectations et les journaux métier.

Ce patch ferme les derniers angles morts côté client Flutter :

- toute clé locale `openirn.*` non explicitement autorisée est supprimée au démarrage ;
- seules les métadonnées publiques nécessaires à l'appairage restent persistées localement ;
- les anciens reliquats local-first sont purgés ;
- l'ancien administrateur local n'est plus traité comme un compte spécial côté client.

## Clés locales autorisées

Les seules clés `SharedPreferences` autorisées avec le préfixe `openirn.` sont :

```text
openirn.sync.configuration
openirn.sync.deviceId
```

Elles ne contiennent pas de donnée métier ni de secret persistant. Elles servent uniquement à retrouver :

- l'URL API fixe ;
- le tenant ;
- l'identifiant public du terminal ;
- l'état d'activation de la synchronisation.

## Clés supprimées

Le service de purge supprime notamment :

```text
openirn.localUsers
openirn.localSession.activeUserId
openirn.localCampaigns.*
openirn.assessment.answers.*
openirn.criterionAssignments.*
openirn.activityLog.*
openirn.sync.log.events
openirn.secureFallback.*
```

Il supprime aussi toute nouvelle clé `openirn.*` non autorisée afin d'éviter une régression vers un stockage local métier.

## Administrateur local historique

L'ancien identifiant `local-admin` est conservé uniquement comme identifiant historique pour ignorer proprement d'anciens exports. Le client ne crée plus d'administrateur local et ne protège plus spécialement un utilisateur serveur portant cet identifiant.

## Tests

Le patch met à jour les tests du service de purge pour vérifier :

- l'inventaire des clés autorisées ;
- la purge des clés métier historiques ;
- la suppression de toute clé `openirn.*` non autorisée.
