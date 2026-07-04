# Patch 173.3 — Préservation des menus déroulés

Ce patch améliore l’expérience utilisateur sur l’écran de notation.

## Objectif

Lorsqu’un utilisateur ouvre un cartouche de pilier IRN puis qu’une mise à jour locale ou distante recharge l’écran, le cartouche ne doit plus se refermer automatiquement.

## Comportement ajouté

- mémorisation en mémoire des piliers ouverts par l’utilisateur ;
- restauration de l’état ouvert/fermé après rechargement des réponses ou des affectations ;
- conservation de l’état pendant les mises à jour automatiques de synchronisation ;
- maintien de l’état interne des cartouches ouverts.

## Périmètre

Le patch modifie uniquement l’écran de notation Flutter :

- `flutter/lib/presentation/assessment/assessment_screen.dart`

Aucun changement serveur, MariaDB, API ou modèle de données.
