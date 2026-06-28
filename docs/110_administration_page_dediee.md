# Patch 110 — Page Administration dédiée

Ce patch réorganise l'accès aux fonctions d'administration depuis l'accueil.

## Changements

- Le cartouche `Administration` de la page d'accueil adopte le même rendu que les deux autres cartouches.
- Le cartouche ne contient plus qu'un seul bouton : `Administrer`.
- Le clic sur `Administrer` ouvre la sélection d'un profil `Administrateur` ou `Pilote IRN`.
- Après validation du code personnel, l'utilisateur accède à une nouvelle page `Administration`.
- La page `Administration` centralise les opérations suivantes :
  - `Gérer les campagnes` ;
  - `Utilisateurs` ;
  - `Maintenance serveur`.

## Fichiers modifiés

- `flutter/lib/presentation/referential/referential_overview_screen.dart`
- `flutter/lib/presentation/admin/administration_screen.dart`

## Application

```bash
cd ~/Desktop/OpenIRN
unzip -o ~/Downloads/patch_110_administration_page_dediee_direct.zip
cd flutter
flutter analyze
flutter run
```
