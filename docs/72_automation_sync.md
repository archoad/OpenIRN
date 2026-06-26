# Patch 072 — automatisation de la synchronisation

Ce patch amorce le mode automatisé OpenIRN :

- indicateur de connexion dans la barre de titre commune ;
- contrôle automatique du serveur via `/sync/status` ;
- synchronisation périodique lorsqu'une campagne est ouverte ;
- publication automatique des modifications locales après un court délai ;
- import automatique du dernier snapshot serveur lorsqu'il est plus récent ;
- import en mode remplacement local, et non plus copie locale ;
- interface de synchronisation simplifiée pour les profils non administrateurs.

## Règle d'intégrité

L'import automatique reste soumis aux contrôles déjà présents :

- type de payload `openirn.syncPush` ;
- `schemaVersion` valide ;
- identifiant de référentiel compatible ;
- checksum du référentiel compatible quand il est présent ;
- critères actifs existants dans le référentiel local.

## Règle de fraîcheur

OpenIRN compare le dernier `serverSyncId` côté serveur avec le journal local :

- si le dernier snapshot est déjà connu localement, rien n'est importé ;
- si le dernier snapshot vient du même appareil, il n'est pas réimporté ;
- si le dernier snapshot vient d'un autre appareil et n'est pas connu localement, il est récupéré puis appliqué.

## Interface

Les paramètres techniques restent accessibles aux administrateurs dans l'écran Synchronisation API.
Les autres rôles voient uniquement la synchronisation automatique.
