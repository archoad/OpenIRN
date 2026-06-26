# Affectations — conservation de la position après saisie

Ce correctif améliore l'UX de l'écran d'affectation des critères.

Avant : après sélection d'un évaluateur, la page rechargeait les affectations et revenait en haut de la liste.

Après : avant le rafraîchissement, l'écran mémorise la position courante du `ListView`. Une fois les données rechargées, il restaure automatiquement la position de défilement, en respectant la taille maximale de la liste.

Cela permet d'affecter plusieurs critères en bas de page sans devoir redescendre manuellement après chaque sélection.

Fichier modifié :

```text
flutter/lib/presentation/assignments/criterion_assignment_screen.dart
```
