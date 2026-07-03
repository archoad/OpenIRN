# Patch 162A — Correction layout suppression d’espace

Ce correctif stabilise le cartouche **Administration → Espaces de travail** après l’ajout du bouton rouge **Supprimer un espace**.

## Problème corrigé

En affichage large, les boutons d’action étaient placés dans une `Column` à l’intérieur d’une `Row` sans largeur contrainte. Flutter pouvait alors recevoir une contrainte de largeur infinie et lever l’erreur :

```text
BoxConstraints forces an infinite width.
```

## Correction

La colonne des boutons est désormais encapsulée dans un `SizedBox(width: 240)`, ce qui donne une largeur finie au bloc d’actions.

## Fichier modifié

- `flutter/lib/presentation/admin/tenant_management_screen.dart`
