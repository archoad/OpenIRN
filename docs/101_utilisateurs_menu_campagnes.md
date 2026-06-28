# Patch 101 — Utilisateurs dans le menu Campagnes

## Objectif

Centraliser l'administration applicative dans le menu `⋮` de la page **Campagnes**.

## Changements

- Ajout de l'entrée **Utilisateurs** dans le menu `⋮` de la page **Campagnes**.
- Accès protégé par la même authentification que :
  - **Gérer les campagnes** ;
  - **Maintenance serveur**.
- Seuls les profils **Administrateur** et **Pilote IRN** peuvent ouvrir la gestion des utilisateurs.
- Suppression de l'entrée **Utilisateurs** depuis le menu `⋮` d'une campagne ouverte, pour éviter le doublon.

## Fichiers modifiés

- `flutter/lib/presentation/campaigns/campaign_list_screen.dart`
- `flutter/lib/presentation/assessment/assessment_screen.dart`
