# Patch 093 — Interface administrateur Historique / Conflits

Ce patch ajoute une vue OpenIRN réservée aux profils `Administrateur` et `Pilote IRN` pour consulter l’état SQLite serveur.

## Page ajoutée

`Historique / conflits`

Accessible depuis le menu d’une campagne ouverte.

## Données affichées

- état serveur SQLite ;
- tenant, endpoint API, nombre de campagnes, révisions et conflits ;
- sélection d’une campagne serveur ;
- conflits détectés pour la campagne ;
- historique des révisions ;
- consultation du payload JSON d’une révision précise.

## Endpoints utilisés

- `GET /campaigns`
- `GET /campaigns/revisions`
- `GET /campaigns/conflicts`
- `GET /campaigns/revision`

Tous les appels utilisent le bearer token configuré dans OpenIRN.
