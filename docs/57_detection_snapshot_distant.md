# Patch 062 — Détection de snapshot serveur plus récent

Ce patch exploite `GET /sync/status` pour comparer le dernier snapshot accepté côté serveur avec le journal de synchronisation local.

## Objectif

OpenIRN affiche maintenant, dans la carte `Statut serveur /sync/status`, un message de fraîcheur :

- **Synchronisation à jour** : le dernier `serverSyncId` serveur est déjà connu localement via un `push` réussi ou un import réussi ;
- **Snapshot distant plus récent disponible** : le serveur contient un snapshot qui n’a pas encore été importé localement ;
- **Aucun snapshot serveur** : le tenant n’a pas encore de snapshot ;
- **Snapshot de cet appareil non journalisé** : le dernier snapshot vient du même deviceId, mais le journal local ne l’a plus, cas possible après réinstallation/nettoyage local ;
- **Comparaison impossible** : le statut serveur n’est pas disponible.

## Règle métier

Une simple récupération `/sync/pull` ne marque pas un snapshot comme intégré localement. Seuls deux évènements sont considérés comme preuve locale :

- `pushSucceeded` ;
- `importSucceeded`.

Cela évite de déclarer la synchronisation à jour juste parce que le client a listé les snapshots distants sans les importer.

## Fichier modifié

- `flutter/lib/presentation/sync/sync_screen.dart`
