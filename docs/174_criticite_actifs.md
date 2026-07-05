# Patch 174 — Criticité des actifs

Ce patch réintroduit la criticité de l'actif dans l'inventaire SI avec une échelle explicite de 1 à 4.

## Interface

Dans la page **Fonctions critiques & actifs**, la boîte de dialogue d'ajout/modification d'un actif contient de nouveau un champ **Criticité de l'actif**.

Valeurs autorisées :

- `1` — faible
- `2` — modérée
- `3` — élevée
- `4` — critique

La liste des actifs affiche aussi la criticité sous la forme `Criticité X/4`.

## API

Les endpoints de création et de modification d'actif valident maintenant le champ `criticality`.

Le serveur accepte les valeurs `1`, `2`, `3`, `4` et les libellés usuels issus d'Excel, par exemple `1/4`, `2 — modérée` ou `Criticité 3`.

## Import/export Excel par SI

L'export Excel par système d'information contient désormais une colonne :

```text
Criticité actif
```

Le fichier Excel contient donc les colonnes suivantes :

```text
ID actif
Nom actif
Type actif
Criticité actif
Description actif
```

La colonne **ID actif** reste protégée en écriture. Les colonnes métier, y compris **Criticité actif**, restent modifiables.

À l'import :

- un actif existant conserve son ID ;
- la criticité importée doit être comprise entre 1 et 4 ;
- pour un nouvel actif, la criticité est obligatoire ;
- pour un actif existant, si la criticité est laissée vide, la valeur déjà présente en base est conservée.
