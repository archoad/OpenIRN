# Patch 155B — Administrateur global depuis n’importe quel espace

Ce correctif aligne l’API serveur avec le comportement attendu de l’interface :
le rôle **Administrateur** est un rôle d’administration globale OpenIRN, même si
la session a été ouverte dans l’espace `default` ou dans un autre espace.

## Correction

Avant ce patch, certaines vues multi-espaces, notamment :

- `Utilisateurs — tous les espaces` ;
- `Terminaux autorisés` en vue administrateur ;

pouvaient être refusées si l’administrateur n’était pas connecté depuis
l’espace technique `archoad`.

Après ce patch :

- un Administrateur peut consulter les utilisateurs de tous les espaces ;
- un Administrateur peut consulter les terminaux et demandes d’enrôlement de tous les espaces ;
- un Administrateur peut administrer un autre espace sans changer de session ;
- un Pilote IRN reste limité à son propre espace.

## Fichier modifié

- `server/openirn-api/app/main.py`
