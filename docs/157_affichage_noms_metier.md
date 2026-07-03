# Patch 157 — Affichage des noms métier

Ce patch complète le passage aux UUID en masquant les identifiants techniques dans l’interface utilisateur.

## Objectif

Les UUID restent utilisés en interne pour les relations et les appels serveur, mais l’application affiche désormais les noms métier :

- nom affiché de l’espace de travail ;
- nom complet ou email de l’utilisateur ;
- nom de campagne ;
- nom du terminal.

## Principales corrections UX

- la sélection d’un espace n’affiche plus l’UUID de l’espace ;
- la page **Espaces de travail** n’affiche plus l’identifiant technique ;
- la page **Utilisateurs** affiche le nom de l’espace, pas l’UUID du tenant ;
- la page **Terminaux autorisés** affiche le nom de l’espace, pas l’UUID du tenant ;
- les messages d’ouverture de session et d’appairage utilisent le nom de l’espace ;
- les fallbacks utilisateur n’affichent plus l’UUID si le nom est absent.

## Côté serveur

Les réponses serveur enrichissent maintenant les objets avec des libellés lisibles quand nécessaire :

- `tenantDisplayName` sur les utilisateurs ;
- `tenantDisplayName` sur les terminaux autorisés ;
- `tenantDisplayName` sur les demandes d’enrôlement ;
- libellés utilisateurs associés aux décisions et invitations quand ils sont disponibles.

