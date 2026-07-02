# Patch 153C — Correction lisibilité PDF

Ce correctif sécurise le rendu PDF de la synthèse IRN.

## Problème corrigé

Le PDF pouvait afficher de grandes formes vectorielles sur la première page. Le problème venait du rendu PDF de barres de progression arrondies avec un rayon très élevé.

## Correction

- suppression des barres de progression vectorielles dans la section `Radar IRN` du PDF ;
- remplacement par une table simple et portable : code, pilier, score, niveau, complétude ;
- remplacement des rayons `999` restants par des rayons courts dans les éléments PDF.

Le PDF reste volontairement plus sobre que la page Flutter : il privilégie la lisibilité, l’archivage et la compatibilité avec les lecteurs PDF.
