# Patch 171.2 — Import/export Excel SI simplifié

Ce patch simplifie le format Excel de l'inventaire SI pour le rendre utilisable par un Pilote IRN ou un contributeur non technique.

## Nouveau format

L'export Excel ne contient plus trois feuilles métier séparées. Il contient désormais :

- `Instructions`
- `Systèmes d'information`

La feuille `Systèmes d'information` contient une ligne par actif, avec les colonnes suivantes :

1. `ID actif`
2. `Fonction critique`
3. `Description fonction`
4. `Système d'information`
5. `Porteur SI`
6. `Description SI`
7. `Nom actif`
8. `Type actif`
9. `Criticité`
10. `Description actif`

Pour déclarer un système d'information sans actif, il suffit de renseigner la fonction critique et le système d'information, puis de laisser les colonnes actif vides.

## Gestion des identifiants

La colonne `ID actif` est affichée pour les actifs existants, mais elle est verrouillée dans le fichier Excel exporté par une protection de feuille avec mot de passe aléatoire interne.

Cette protection évite les modifications accidentelles de l'identifiant. Elle ne doit pas être considérée comme un chiffrement de sécurité fort du document.

À l'import :

- si `ID actif` correspond à un actif existant de l'espace courant, l'actif est réécrit avec les nouvelles données de la ligne ;
- si `ID actif` est vide, ou ne correspond pas à un actif existant, OpenIRN crée automatiquement un nouvel identifiant ;
- les fonctions critiques et systèmes d'information sont reconstruits à partir des libellés du fichier.

## Portée de l'import

L'import remplace l'inventaire SI de l'espace courant : fonctions critiques, systèmes d'information et actifs.

Il ne modifie pas :

- les campagnes ;
- les notes IRN ;
- les utilisateurs ;
- les terminaux ;
- les espaces de travail.
