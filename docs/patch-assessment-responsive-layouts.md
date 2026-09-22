# Préparation des layouts responsives de l’évaluation

## Objectif

Préparer l’écran d’évaluation pour trois compositions visuelles — smartphone,
tablette et grand écran — tout en conservant un état métier unique et les
composants d’évaluation partagés.

## Fichiers concernés

- `flutter/lib/presentation/assessment/assessment_screen.dart`
- `flutter/test/assessment_screen_layout_test.dart`

## Changements

- seuils responsives centralisés : compact avant 700 px, medium de 700 à
  1099 px et wide à partir de 1100 px ;
- trois widgets de composition explicites alimentés par les mêmes sections et
  callbacks issus de `_AssessmentScreenState` ;
- composition large en maître/détail avec contexte, affectations et actifs à
  gauche, puis score, persistance et critères à droite ;
- fond de la barre latérale large basé sur `surfaceContainerHigh` afin de la
  distinguer des cartes sans introduire une couleur hors thème ;
- palette visuelle centralisée des piliers RES-1 à RES-8 : chaque couleur
  demandée dessine le contour du cartouche correspondant et génère son fond
  pastel, avec sélection automatique d’un texte offrant un contraste d’au
  moins 4,5:1 ;
- masquage complet des cartouches d’informations de campagne et d’affectations
  lorsque le profil actif ne possède pas la permission de gestion associée ;
- affichage des critères sur deux colonnes uniquement à partir de 960 px de
  largeur utile ;
- cartouche d’affectations empilé lorsqu’il dispose de moins de 520 px ;
- piliers conservés comme enfants directs des listes défilantes afin de
  préserver leur construction paresseuse et les performances sur grand écran ;
- test des seuils, du rendu des trois layouts et de la conservation de la même
  instance d’état pendant un redimensionnement ;
- test de non-régression vérifiant qu’un pilier hors écran n’est pas construit
  tant qu’il n’entre pas dans la zone visible.

## Invariants préservés

- aucun changement du modèle serveur ou des contrats API ;
- aucun changement du stockage des réponses et justifications ;
- aucun changement des permissions ou de la synchronisation ;
- aucun changement du calcul de score ou de la synthèse ;
- aucune migration et aucune nouvelle chaîne traduisible.

## Validation locale

Environnement : Flutter 3.47.4, Dart 3.13.3.

```bash
cd flutter
dart format --output=none --set-exit-if-changed \
  lib/presentation/assessment/assessment_screen.dart \
  test/assessment_screen_layout_test.dart
flutter analyze
flutter test test/assessment_screen_layout_test.dart
flutter test
```

Résultats : analyse statique sans anomalie, test responsive ciblé réussi et
95 tests Flutter réussis.
