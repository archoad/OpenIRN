# Patch 060 — Journal de synchronisation local

Ce patch ajoute un journal local dédié aux opérations de synchronisation API.

## Évènements tracés

- test de connexion `/health` ;
- envoi `/sync/push` réussi ou refusé ;
- récupération `/sync/pull` réussie ou refusée ;
- import d’un snapshot distant réussi ou refusé.

Le journal est local à l’appareil et stocké dans `shared_preferences`.
Il conserve les 300 derniers évènements.

## Interface

L’écran `Synchronisation API` ajoute une action `Journal de synchronisation` dans la barre d’application.

L’écran affiche :

- le nombre total d’évènements ;
- le nombre de succès / alertes ;
- le tenant ;
- l’appareil ;
- les statuts HTTP ;
- les `serverSyncId` ;
- le nombre de campagnes ou snapshots concernés.

## Périmètre

Ce journal n’est pas encore synchronisé avec le serveur.
Il sert de traçabilité locale côté client.
