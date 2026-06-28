# 109 — Administration depuis la page d'accueil

## Objectif

Regrouper les fonctions d'administration au niveau de la page d'accueil afin de rendre la page **Campagnes** plus lisible et plus métier.

## Changements

- Suppression du menu `⋮` de la page **Campagnes**.
- Ajout d'un troisième cartouche **Administration** sur la page d'accueil, sous le cartouche **Référentiel aDRI IRN**.
- Le cartouche **Administration** donne accès à :
  - **Gérer les campagnes** ;
  - **Utilisateurs** ;
  - **Maintenance serveur**.
- Chaque action reste protégée par une authentification avec un profil :
  - **Administrateur** ;
  - **Pilote IRN**.
- Le pavé numérique Flutter sécurisé reste utilisé sur smartphone pour éviter l'ouverture du clavier natif iOS pendant la saisie du code personnel.

## Impact UX

La page d'accueil contient désormais trois cartouches :

1. **Evaluation Indice de Résilience Numérique** ;
2. **Référentiel aDRI IRN** ;
3. **Administration**.

La page **Campagnes** ne contient plus de menu d'administration et se concentre sur l'ouverture des campagnes d'évaluation.
