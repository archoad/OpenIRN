# Patch 122 — Verrouillage du premier lancement

## Objectif

Ce patch corrige deux comportements de sécurité sur la page d’accueil :

- au premier lancement, tant que le terminal n’est pas autorisé, les entrées **Evaluation Indice de Résilience Numérique** et **Administration** ne sont plus affichées ;
- l’administration ne peut plus s’ouvrir à partir de la base utilisateurs locale de secours sans authentification serveur.

## Nouveau comportement

### Terminal non autorisé

La page d’accueil affiche uniquement :

- **Référentiel aDRI IRN** ;
- **Autoriser ce terminal**.

Les campagnes et l’administration deviennent visibles seulement après appairage du terminal.

### Administration

L’ouverture de la page **Administration** nécessite désormais :

1. un terminal autorisé ;
2. une base utilisateurs récupérée depuis le serveur ;
3. une authentification par code personnel côté serveur.

La base locale de secours n’est plus utilisée pour ouvrir l’administration.

## Fichier modifié

- `flutter/lib/presentation/referential/referential_overview_screen.dart`
