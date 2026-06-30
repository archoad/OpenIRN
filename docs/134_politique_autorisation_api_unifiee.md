# Patch 134 — Politique d’autorisation API unifiée

Ce patch centralise les règles d’autorisation côté API OpenIRN.

## Objectif

OpenIRN fonctionne maintenant avec :

- un `deviceId` public qui identifie un terminal enrôlé ;
- une session serveur courte conservée uniquement en mémoire côté client ;
- un bearer serveur de transition pour les opérations d’administration d’urgence.

Le `deviceId` ne doit donc jamais donner de droits d’écriture ou d’administration.

## Politique appliquée

### Lecture simple

Acceptée avec :

- bearer de transition ;
- session serveur courte ;
- ancien jeton terminal de transition ;
- terminal actif via `X-OpenIRN-Device-Id`.

Endpoints concernés :

- `/sync/status` ;
- `/sync/pull` ;
- `/sync/events` ;
- `/campaigns` ;
- `/users` ;
- `/referential/official/current`.

### Écriture métier

Acceptée uniquement avec :

- bearer serveur de transition ;
- session serveur courte d’un profil ayant des droits d’écriture.

Rôles autorisés :

- Administrateur ;
- Pilote IRN ;
- Évaluateur ;
- Validateur.

Endpoint concerné :

- `/sync/push`.

### Administration stricte

Acceptée uniquement avec :

- bearer serveur de transition ;
- session serveur courte Administrateur.

Endpoints concernés :

- terminaux autorisés ;
- utilisateurs ;
- sessions serveur ;
- journal sécurité ;
- référentiel officiel ;
- maintenance serveur.

### Pilotage campagne

Accepté uniquement avec :

- bearer serveur de transition ;
- session serveur courte Administrateur ou Pilote IRN.

Endpoints concernés :

- `/campaigns/revisions` ;
- `/campaigns/conflicts` ;
- `/campaigns/revision` ;
- `/campaigns/restore`.

## Compatibilité

Le bearer de transition reste accepté pour les opérations d’administration et d’écriture afin de conserver une procédure d’urgence côté serveur.

Les anciens jetons terminaux restent acceptés uniquement pour les lectures pendant la période de transition. Ils ne sont plus acceptés pour les endpoints d’écriture ou d’administration.
