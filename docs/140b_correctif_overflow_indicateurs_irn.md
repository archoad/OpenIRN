# Patch 140B — Correctif overflow indicateurs IRN

## Objectif

Corriger les débordements `RenderFlex overflowed` observés dans les tuiles des 8 piliers sur la page **Synthèse**.

## Cause

La grille ajoutée au patch 140 utilisait des ratios trop larges (`1.18` et `1.12`), ce qui produisait des tuiles trop basses lorsque la largeur disponible diminuait. Le contenu interne pouvait alors dépasser de quelques pixels, voire davantage pour les libellés longs.

## Correction

Le patch ajuste uniquement le bloc d'indicateurs IRN :

- ratio de grille plus carré et plus haut :
  - 4 colonnes : `1.0` ;
  - 2 colonnes : `0.95` ;
- padding légèrement réduit sur les tuiles compactes ;
- titre des piliers limité à 2 lignes ;
- sous-titre compact limité à 1 ligne.

## Effet attendu

Le bloc garde la structure demandée :

- score global à gauche ;
- 8 carrés de piliers à droite ;
- couleurs rouge → vert selon la note ;
- aucun overflow Flutter sur les largeurs intermédiaires.
