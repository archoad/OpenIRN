# Patch 175 — Formule de maturité IRN

Ce patch intègre la formule de notation fournie par les porteurs de la norme IRN.

## Principe

Une campagne créée depuis un système d'information note chaque actif du SI. La note affichée pour le SI n'est plus une moyenne arithmétique simple de tous les critères : elle devient une maturité IRN consolidée.

## Étape 1 — score de critère

Les valeurs de la grille restent :

- `N.C.` : non concerné, exclu du score et inclus dans la complétude ;
- `Non résilient` : 10/100 ;
- `Intention` : 25/100 ;
- `Moyen` : 50/100 ;
- `Résultat` : 95/100.

## Étape 2 — pré-score E d'un actif

Pour chaque actif, OpenIRN calcule d'abord un score par pilier RES à partir des critères cotés du pilier.

Le pré-score `E` de l'actif est la moyenne géométrique des scores de piliers renseignés :

```text
E = EXP( MOYENNE( LN(score pilier RES) ) )
```

Les piliers sans critère coté ne participent pas encore au calcul du pré-score de l'actif.

## Étape 3 — criticité D

Chaque actif porte une criticité `D` de 1 à 4 :

- 1 — faible ;
- 2 — modérée ;
- 3 — élevée ;
- 4 — critique.

## Étape 4 — score du SI

Le score de maturité IRN du SI est la moyenne géométrique pondérée des pré-scores d'actifs :

```text
Score SI = EXP( SOMME( D × LN(E) ) ÷ SOMME(D) )
```

Un actif critique mal noté pèse donc plus fortement sur le score du SI qu'un actif peu critique.

## Interface

Le menu `⋮` d'une campagne contient une nouvelle page `Calcul de la note`, qui explique la formule.

Dans une campagne par SI :

- le cartouche `Score IRN` affiche la maturité consolidée du SI ;
- le cartouche `Notation par actif` sert toujours à choisir l'actif à évaluer ;
- les boutons d'actifs affichent la criticité `C1` à `C4` ;
- la synthèse de campagne reprend la maturité du SI et conserve les indicateurs de complétude.

## Compatibilité

Les campagnes non créées depuis un SI conservent le calcul simple par grille IRN.

Les campagnes SI existantes dont les actifs ne portent pas encore de criticité explicite sont interprétées avec une criticité par défaut `1`.
