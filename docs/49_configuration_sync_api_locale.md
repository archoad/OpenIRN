# Patch 051 — configuration de synchronisation API locale

Ce lot ajoute la première brique visible de synchronisation serveur, sans envoi HTTP réel.

## Objectif

OpenIRN peut maintenant :

- enregistrer une URL d'API serveur ;
- enregistrer un identifiant d'organisation / tenant ;
- générer et conserver un identifiant local d'appareil ;
- produire un payload JSON `openirn.syncPush` contenant les données locales prêtes à envoyer.

## Périmètre volontairement limité

Ce patch ne fait pas encore :

- authentification distante ;
- appel HTTP réel ;
- résolution de conflits ;
- pull serveur ;
- stockage serveur.

L'objectif est de stabiliser le contrat de données local avant d'ajouter le client HTTP.

## Parcours utilisateur

```text
Campagnes locales
 → Synchronisation
 → Configurer API / tenant
 → Préparer payload /sync/push
 → Copier le JSON
```

## Données incluses dans le payload

- session active ;
- référentiel utilisé ;
- utilisateurs locaux ;
- campagnes locales ;
- réponses et justifications ;
- affectations ;
- journal d'activité ;
- compteurs de synthèse.

## Contrat API

Le brouillon `api/openapi_sync_draft.yaml` passe en version `0.2.0` et décrit la structure cible de `/sync/push`.
