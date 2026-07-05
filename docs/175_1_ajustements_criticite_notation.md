# Patch 175.1 — Ajustements criticité et libellés de notation

Ce patch ajuste les libellés de criticité et la page de calcul de la note après intégration de la formule de maturité IRN.

## Changements

- La criticité de niveau 1 est libellée `standard` au lieu de `faible`.
- Les badges de criticité des actifs utilisent `N1`, `N2`, `N3`, `N4` au lieu de `C1`, `C2`, `C3`, `C4`.
- La page d'évaluation recharge les métadonnées d'actifs du SI depuis l'inventaire serveur quand c'est possible, afin d'afficher la criticité réellement saisie en base.
- La page **Calcul de la note** remplace `1 · Note d’un critère` par `1 · Notation d’un actif`.
- La phrase d'explication devient : `La maturité de chaque actif est évaluée selon la grille IRN`.

## Notes

Le rechargement de l'inventaire est non bloquant : si le serveur est indisponible, l'évaluation reste possible avec les métadonnées embarquées dans la campagne.
