# Patch 140D — Hauteur du score global alignée sur la grille IRN

## Objectif

Améliorer l’UX du bloc **Indicateurs IRN** ajouté sur la page **Synthèse**.

Le carré **Score global** doit avoir la même hauteur que les deux lignes de carrés des piliers, afin de reprendre plus fidèlement la mise en page observée dans la présentation IRN.

## Comportement

En affichage large :

- le score global est affiché dans un carré à gauche ;
- les 8 piliers sont affichés à droite dans une grille 4 × 2 ;
- la dimension du carré global est calculée pour être exactement égale à la hauteur totale des deux lignes de la grille.

En affichage plus étroit :

- le mode vertical responsive est conservé ;
- le score global reste au-dessus de la grille.

## Implémentation

Le patch ajoute le helper `_wideIndicatorBoardHeight()` dans :

```text
flutter/lib/presentation/assessment/assessment_summary_screen.dart
```

Ce helper calcule la hauteur commune à partir :

- de la largeur disponible ;
- de l’espace entre le carré global et la grille ;
- de l’espacement entre les tuiles ;
- du nombre de colonnes/lignes de la grille ;
- du ratio de chaque tuile pilier.
