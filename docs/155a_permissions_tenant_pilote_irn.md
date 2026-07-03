# Patch 155A — Permissions tenant du Pilote IRN

Ce correctif sépare les permissions d'administration globale et les permissions d'administration limitées à l'espace de travail.

## Objectif

Le rôle **Pilote IRN** doit pouvoir administrer les utilisateurs et les terminaux de son propre espace, sans obtenir les permissions de sécurité plateforme réservées à l'Administrateur.

## Changements

- ajout de permissions tenant-scopées pour les utilisateurs ;
- ajout de permissions tenant-scopées pour les terminaux autorisés ;
- conservation des permissions globales `manageUsers` et `manageAuthorizedDevices` pour l'Administrateur uniquement ;
- adaptation de la page Administration pour afficher les cartouches Pilote IRN à partir des permissions tenant-scopées.
