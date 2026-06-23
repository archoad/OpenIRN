# Patch 029 — Informations de campagne depuis la campagne ouverte

Ce patch déplace la saisie des informations détaillées de campagne depuis la liste des campagnes vers l'écran d'une campagne ouverte.

## Nouveau comportement

- La création d'une campagne depuis la liste ne demande plus que :
  - le nom de la campagne ;
  - la description de la campagne.
- Les informations détaillées sont saisies après ouverture de la campagne :
  - nom du système d'information ;
  - description du système d'information ;
  - prénom, nom et email du directeur de projet.
- L'écran de campagne affiche un bouton `Informations` dans la barre d'action et un bouton `Modifier les informations de campagne` dans la carte de contexte.
- Les campagnes validées ou archivées restent en lecture seule.

## Contrôle qualité

Le contrôle qualité continue d'exiger que les informations de campagne soient complètes avant le passage au statut `Prêt pour revue`.

## Export JSON

L'export JSON conserve les champs introduits dans le schéma version 5. Aucun changement de schéma n'est nécessaire.
