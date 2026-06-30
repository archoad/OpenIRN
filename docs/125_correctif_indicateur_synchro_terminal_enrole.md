# Patch 125 — Indicateur de synchronisation pour terminal enrôlé

## Problème

Après l'enrôlement d'un terminal, l'application récupérait bien les données initiales, mais l'indicateur de connexion restait rouge. Les logs serveur indiquaient des refus `403` sur :

- `GET /sync/events?tenantId=...`
- `GET /sync/status?tenantId=...`

Ces endpoints exigeaient encore un bearer ou un jeton de session, alors que le niveau 1 de sécurité retenu pour OpenIRN ne stocke plus de secret persistant localement.

## Correction

Ajout d'un garde d'accès lecture seule :

- bearer historique accepté pendant la transition ;
- session courte en mémoire acceptée ;
- ancien jeton terminal accepté pendant la transition ;
- terminal actif accepté via `X-OpenIRN-Device-Id` pour les endpoints de lecture de synchronisation.

Les endpoints d'écriture restent protégés par un bearer/session token.

## Endpoints concernés

- `GET /sync/status`
- `GET /sync/events`

## Test

Après redémarrage de l'API, un terminal enrôlé doit pouvoir ouvrir le flux SSE et obtenir le statut serveur sans 403. L'indicateur de connexion doit passer au vert.
