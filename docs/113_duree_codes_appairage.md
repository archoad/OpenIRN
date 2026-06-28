# Patch 113 — Durée des codes d’appairage

Ce patch limite la durée de validité des codes d’appairage de terminaux à trois choix :

- 5 minutes ;
- 10 minutes ;
- 15 minutes.

## Interface

La page `Administration → Terminaux autorisés → Autoriser un nouveau terminal` ne propose plus les durées 30 et 60 minutes.

## Serveur

L’endpoint `POST /devices/enrollment` force désormais toute valeur invalide à 10 minutes. Cela évite qu’un client ancien ou modifié crée une invitation avec une durée non prévue.
