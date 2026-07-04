# Patch 134 — Politique d’autorisation API unifiée

## Objectif

Centraliser les décisions d’autorisation serveur afin de distinguer clairement :

- les sessions serveur courtes associées à un utilisateur et à un rôle ;
- les jetons de terminal, limités à l’identité technique du terminal ;
- l’identifiant public du terminal, utilisable pour certains accès de lecture ;
- les opérations d’administration et d’écriture, réservées aux sessions serveur autorisées.

## Mise à jour 163B

Le bearer global historique est déprécié :

- `Authorization: Bearer` reste le schéma HTTP utilisé par les sessions serveur ;
- `OPENIRN_API_TOKEN` est désactivé par défaut ;
- même réactivé explicitement pour migration, le bearer global legacy ne donne plus de droits d’écriture ni d’administration ;
- les opérations sensibles exigent une session serveur `ost_…` et un rôle compatible ;
- les sauvegardes utilisent `OPENIRN_API_BACKUP_SIGNATURE_SECRET`, jamais `OPENIRN_API_TOKEN` comme secret de secours.

## Règles par niveau

### Lecture et connectivité

Les endpoints de lecture nécessaires au démarrage peuvent accepter :

- une session serveur valide ;
- un jeton de terminal legacy encore actif ;
- un terminal actif identifié par `X-OpenIRN-Device-Id` quand l’endpoint le permet ;
- temporairement, le bearer global legacy si `OPENIRN_LEGACY_GLOBAL_BEARER_ENABLED=true` est configuré côté serveur.

### Écriture métier

Les opérations d’écriture exigent une session serveur avec l’un des rôles autorisés :

- Administrateur ;
- Pilote IRN ;
- Évaluateur ;
- Relecteur, selon l’opération.

### Administration

Les opérations d’administration exigent une session serveur d’un utilisateur Administrateur, ou Administrateur/Pilote IRN lorsque l’endpoint le prévoit explicitement.

Un jeton de terminal ou le bearer global legacy ne suffit pas.

## Conséquence pratique

Le header reste visuellement identique :

```http
Authorization: Bearer ost_...
```

La différence est dans la nature du token : il s’agit maintenant d’une session courte contrôlée par le serveur, et non d’un secret global partagé.
