# Patch 171.3 — Import/export Excel des actifs par SI

Ce patch recentre l'import/export Excel sur le système d'information affiché dans l'interface.

## Interface

Chaque cartouche de système d'information affiche désormais deux actions :

- **Importer Excel** ;
- **Exporter Excel**.

Les boutons d'import/export globaux de la page ont été retirés.

## Format Excel

L'export d'un SI contient une seule feuille `Actifs SI` avec les colonnes :

1. `ID actif` ;
2. `Nom actif` ;
3. `Type actif` ;
4. `Description actif`.

La colonne `ID actif` est verrouillée par protection Excel avec un mot de passe aléatoire généré à l'export. Les colonnes `Nom actif`, `Type actif` et `Description actif` sont déverrouillées et modifiables.

Cette protection évite les modifications accidentelles de l'identifiant. Elle ne constitue pas un chiffrement fort du fichier.

## Import

L'import agit uniquement sur le SI concerné :

- un `ID actif` existant met à jour l'actif correspondant ;
- une ligne avec `ID actif` vide crée automatiquement un nouvel actif ;
- un `ID actif` inconnu pour ce SI provoque une erreur explicite ;
- les actifs absents du fichier sont retirés de ce SI ;
- les fonctions critiques, les systèmes d'information, les campagnes et les notes IRN ne sont pas modifiés.

## Criticité

La criticité n'est plus saisissable dans l'interface des actifs et n'est plus présente dans l'Excel.
Le champ reste en base à vide pour compatibilité technique.
