# Patch 063 — Correctifs synchronisation iOS

Ce patch corrige deux problèmes observés lors des tests sur iPhone :

- débordement horizontal des boutons dans les cartes de synchronisation sur écran étroit ;
- crash `Null check operator used on a null value` lors du clic sur `Statut serveur` lorsque le `FormState` est temporairement indisponible après reconstruction de l'écran.

## Changements

- Ajout d'un composant `_ResponsiveCardHeader` qui place les boutons en `Wrap` sur les écrans étroits.
- Application de ce composant aux cartes :
  - `Payload /sync/push` ;
  - `Statut serveur /sync/status` ;
  - `Snapshots distants /sync/pull`.
- Remplacement des appels ` _formKey.currentState!.validate()` par une validation sûre.

## Validation

```bash
cd flutter
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d macos
flutter run -d <device-ios>
```
