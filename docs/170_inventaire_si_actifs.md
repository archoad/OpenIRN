# Patch 170 — Inventaire SI des fonctions critiques et actifs

Ce patch introduit la première brique métier demandée par les porteurs de la norme IRN : la notation IRN s’applique désormais à terme sur les actifs d’un système d’information, eux-mêmes rattachés à une fonction critique.

## Modèle ajouté

Dans un espace de travail OpenIRN :

- une fonction critique représente un service/processus métier à protéger ;
- un système d’information porte une fonction critique ;
- un actif appartient à un système d’information.

Le stockage MariaDB ajoute trois tables :

- `critical_functions` ;
- `information_systems` ;
- `information_assets`.

Les suppressions sont en cascade : supprimer une fonction critique supprime les SI associés et leurs actifs ; supprimer un SI supprime ses actifs.

## Interface

Un nouveau cartouche apparaît dans l’accueil d’administration des profils Administrateur et Pilote IRN :

**Fonctions critiques, SI & actifs**

Il permet de :

- créer, modifier et supprimer une fonction critique ;
- créer, modifier et supprimer un système d’information rattaché à une fonction ;
- créer, modifier et supprimer un actif rattaché à un SI.

## API

Endpoints ajoutés :

- `GET /inventory` ;
- `POST /inventory/critical-functions` ;
- `PATCH /inventory/critical-functions/{function_id}` ;
- `DELETE /inventory/critical-functions/{function_id}` ;
- `POST /inventory/information-systems` ;
- `PATCH /inventory/information-systems/{system_id}` ;
- `DELETE /inventory/information-systems/{system_id}` ;
- `POST /inventory/assets` ;
- `PATCH /inventory/assets/{asset_id}` ;
- `DELETE /inventory/assets/{asset_id}`.

Toutes ces routes exigent une session serveur Administrateur ou Pilote IRN dans l’espace de travail concerné.

## Limite volontaire

Ce patch ne rattache pas encore une campagne ou une note IRN à un actif. Il pose uniquement le modèle et l’écran de gestion. Les étapes suivantes pourront ajouter :

- sélection d’un actif au moment de créer une campagne ;
- rattachement des réponses IRN à l’actif évalué ;
- tableaux de bord par fonction critique, SI et actif.
