# Patch 112 — Correctif overflow dialogue code utilisateur

## Objectif

Corriger le débordement Flutter observé dans la page **Utilisateurs** lors de l'ouverture de la fenêtre **Modifier le code utilisateur**.

Erreur constatée :

```text
A RenderFlex overflowed by 2.3 pixels on the bottom.
Column:file:///.../flutter/lib/presentation/users/user_list_screen.dart:894:18
```

## Cause

Le contenu du dialogue était organisé dans une `Column` à hauteur minimale. Sur certaines tailles d'écran, ou lorsque l'espace disponible est réduit par le système, la hauteur disponible peut devenir légèrement inférieure à la hauteur naturelle du formulaire.

## Correction

Le formulaire de modification du code utilisateur est maintenant placé dans un `SingleChildScrollView`.

Cela permet :

- d'éviter le débordement vertical ;
- de conserver l'affichage compact lorsque tout tient à l'écran ;
- de permettre le défilement si l'espace disponible devient insuffisant ;
- de garder le comportement compatible macOS, Windows, iOS, iPadOS et Android.

## Fichier modifié

```text
flutter/lib/presentation/users/user_list_screen.dart
```
