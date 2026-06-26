# Patch 069 — Page utilisateurs responsive

Ce patch remplace la mise en page `ListTile + trailing` de la page utilisateurs par une carte adaptative.

## Changements

- cartes utilisateurs responsives sur smartphone ;
- suppression des débordements horizontaux liés au `trailing` ;
- rôles, descriptions, chips et actions passent à la ligne proprement ;
- le formulaire utilisateur devient aussi plus confortable sur écran étroit ;
- le menu d’action de l’AppBar reste inchangé.

## Validation

```bash
cd flutter
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d macos
flutter run -d <id-iphone>
```
