# Patch 171.4 — Correctif protection Excel actifs par SI

Ce correctif ajuste la protection de la feuille Excel exportée depuis un cartouche de système d'information.

## Correction

La colonne `ID actif` reste verrouillée afin d'éviter la modification accidentelle des identifiants techniques.

Les colonnes suivantes restent éditables :

- `Nom actif`
- `Type actif`
- `Description actif`

## Détail technique

Le patch corrige le paramètre `selectUnlockedCells` de la protection de feuille. Avec certains lecteurs Excel/LibreOffice, la valeur précédente empêchait aussi la sélection et l'édition des cellules pourtant déverrouillées.
