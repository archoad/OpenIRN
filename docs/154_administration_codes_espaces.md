# Patch 154 — Administration des espaces et changement de code

Ce patch ajoute trois améliorations de finitions avant stabilisation post-1.0.0.

## Espaces de travail

Dans **Administration → Espaces de travail**, un administrateur peut désormais renommer un espace de travail existant.

- l’identifiant technique de l’espace reste inchangé ;
- seul le nom affiché est modifié ;
- l’action est journalisée côté serveur.

## Changement de code personnel

Les utilisateurs connectés peuvent changer leur propre code d’accès sans intervention d’un administrateur.

Le changement demande :

- le code actuel ;
- le nouveau code ;
- la confirmation du nouveau code.

Le serveur vérifie le code actuel avant de remplacer l’empreinte stockée.

## Emplacement dans l’interface

- Sur la page d’accueil, les profils **Évaluateur**, **Valideur** et **Lecteur** disposent d’un cartouche **Administration** pour changer leur code.
- Dans la page **Administration**, les profils **Pilote IRN** et **Administrateur** disposent d’un cartouche **Changement de code**.
