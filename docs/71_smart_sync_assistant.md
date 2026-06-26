# Patch 071 — Assistant de synchronisation

Ce patch ajoute un flux guidé dans l'écran `Synchronisation API`.

## Objectif

Réduire le flux manuel :

```text
Statut serveur → Récupérer → Importer ou Envoyer
```

à une action plus simple :

```text
Synchroniser maintenant
```

## Comportement

Le bouton effectue d'abord un contrôle `/sync/status`.

- Si le serveur est inaccessible ou si le token est refusé, l'opération s'arrête avec un message clair.
- Si le dernier snapshot serveur provient d'un autre appareil et n'est pas connu localement, OpenIRN lance la récupération du dernier snapshot et propose son import.
- Si aucun snapshot distant plus récent n'est détecté, OpenIRN pousse le snapshot local avec `/sync/push`.

L'import distant reste non destructeur et demande toujours confirmation.
