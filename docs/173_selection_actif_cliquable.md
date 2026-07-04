# Patch 173 — Sélection d’actif cliquable dans la notation

Ce patch simplifie l’écran de notation des campagnes créées depuis un système d’information.

## Changements

- Le cartouche **Notation par actif** ne contient plus de liste déroulante.
- Chaque actif est affiché comme une ligne cliquable avec :
  - son libellé ;
  - son niveau de progression ;
  - une barre de progression ;
  - sa description lorsqu’elle existe.
- Cliquer sur un actif sélectionne directement la grille IRN correspondante.
- Les réponses restent enregistrées séparément par actif.

## Fichier modifié

- `flutter/lib/presentation/assessment/assessment_screen.dart`
