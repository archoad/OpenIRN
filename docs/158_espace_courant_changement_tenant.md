# Patch 158 — Nom de l’espace courant dans le changement d’espace

Ce patch améliore le cartouche **Changer d’espace de travail** sur la page d’accueil OpenIRN.

## Changement UX

Lorsque l’utilisateur est sur la page d’accueil avant ouverture de session, le cartouche affiche désormais explicitement le nom de l’espace courant :

```text
Espace actuel : <nom de l’espace>. Revenir au choix de l’espace de travail OpenIRN avant d’ouvrir une session.
```

Le cartouche **Autoriser ce terminal** utilise aussi le même nom métier quand il est disponible.

## Fichier modifié

- `flutter/lib/presentation/referential/referential_overview_screen.dart`
