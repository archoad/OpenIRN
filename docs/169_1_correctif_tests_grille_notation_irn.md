# Patch 169.1 — Correctif tests grille de notation IRN

## Objet

Le patch 169 remplace l'ancienne valeur `IrnAnswer.resilient` par la nouvelle grille IRN :

- `notConcerned` : N.C.
- `nonResilient` : Non résilient, 10/100
- `intention` : Intention, 25/100
- `medium` : Moyen, 50/100
- `result` : Résultat, 95/100

Les tests Flutter historiques référençaient encore `IrnAnswer.resilient`, ce qui empêchait `flutter analyze` et `flutter test` de compiler.

## Changements

- remplacement de `IrnAnswer.resilient` par `IrnAnswer.result` dans les tests ;
- mise à jour des scores attendus :
  - Résultat + Non résilient = `(95 + 10) / 2 = 52.5` ;
  - Résultat seul = `95` ;
- mise à jour de l'export attendu `RESULTAT` au lieu de `R`.

## Application

Archive overlay directe :

```bash
cd ~/Desktop/openIRN
unzip -o ~/Downloads/openirn_patch_169_1_tests_grille_notation_overlay.zip
flutter analyze
flutter test
```
