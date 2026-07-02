# Patch 141A — Légende et couleurs des indicateurs IRN

## Objectif

Ajuster la légende du bloc **Indicateurs IRN** et rendre les couleurs plus franches.

## Changements UX

La légende devient :

- **Faible** — vert ;
- **Modéré** — jaune ;
- **Haut** — orange ;
- **Critique** — rouge ;
- **Non coté** — gris.

## Seuils appliqués

Les couleurs restent cohérentes avec une note OpenIRN R/NR où une note élevée est favorable :

- `80–100` : Faible / vert ;
- `60–79` : Modéré / jaune ;
- `40–59` : Haut / orange ;
- `0–39` : Critique / rouge.

Le libellé représente donc le **niveau d’attention associé au score**, pas une nouvelle méthode de calcul.

## Périmètre

Le patch ne modifie pas :

- le moteur de scoring ;
- les données de campagne ;
- les exports ;
- le radar des piliers.
