# Patch 177 — Internationalisation Administration et code d’accès

Ce patch poursuit la transition bilingue FR/EN amorcée par le patch 176.

## Périmètre migré

- page **Administration** ;
- cartouches d’administration ;
- messages d’accès refusé de l’administration ;
- carte **Changement de code** ;
- dialogue de changement de code ;
- libellés et validations du formulaire de code ;
- rôles utilisateur affichés dans le bandeau de session administration.

## Principe

Les textes restent passés sous forme de libellés français dans les widgets existants, mais sont maintenant résolus via le helper de transition `context.trText(...)`.

Les correspondances sont ajoutées dans :

- `flutter/assets/i18n/fr.json`
- `flutter/assets/i18n/en.json`

Cette approche permet de migrer progressivement les écrans sans modifier immédiatement toutes les signatures de widgets.

## Validation attendue

```bash
cd ~/Desktop/openIRN
unzip -o ~/Downloads/openirn_patch_177_i18n_administration_overlay.zip
cd flutter
flutter analyze
flutter test
```
