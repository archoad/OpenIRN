# Patch 145 — Tenant affiché dans le cartouche Session ouverte

## Objectif

Afficher clairement le tenant actif dans le cartouche **Session ouverte** de la page principale.

## Changement

Le cartouche affiche maintenant :

- l’utilisateur connecté ;
- son rôle ;
- le tenant courant ;
- l’expiration serveur ;
- l’heure de verrouillage automatique.

Le tenant `default` est affiché sous la forme `Défaut (default)` pour éviter une lecture trop technique.
