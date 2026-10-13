# Interface d’évaluation responsive et identité visuelle

## Objectif

Proposer trois compositions visuelles de l’écran d’évaluation — smartphone,
tablette et grand écran — tout en conservant un état métier unique, puis
harmoniser la typographie et les repères des huit piliers dans toute
l’application.

## Fichiers concernés

- `flutter/lib/presentation/assessment/assessment_screen.dart`
- `flutter/lib/presentation/common/irn_pillar_palette.dart`
- `flutter/lib/main.dart`
- `flutter/pubspec.yaml`
- `flutter/assets/fonts/`
- `flutter/test/assessment_screen_layout_test.dart`
- `flutter/test/app_theme_test.dart`
- `flutter/test/irn_pillar_palette_test.dart`

## Changements

- seuils responsives centralisés : compact avant 700 px, medium de 700 à
  1099 px et wide à partir de 1100 px ;
- trois widgets de composition explicites alimentés par les mêmes sections et
  callbacks issus de `_AssessmentScreenState` ;
- composition large en maître/détail avec contexte, affectations et actifs à
  gauche, puis score, persistance et critères à droite ;
- fond de la barre latérale large basé sur `surfaceContainerHigh` afin de la
  distinguer des cartes sans introduire une couleur hors thème ;
- police Inter embarquée localement en graisses 400 à 800, utilisée par le
  thème Flutter et les exports PDF, avec sa licence SIL OFL 1.1 ;
- hiérarchie typographique Material rééquilibrée : Display `28/24/22`,
  Headline `22/20/18`, Title `18/14/13`, Body `14/13/12` et Label `12/11/10` ;
- agrandissement de texte configuré par le système conservé, notamment à 200 %,
  sans facteur local qui neutraliserait l’accessibilité ;
- palette visuelle centralisée des piliers : RES-1 bleu royal `#1E40AF`, RES-2
  or ocre `#A16207`, RES-3 violet `#7E22CE`, RES-4 orange cuivré `#C2410C`,
  RES-5 turquoise profond `#0F766E`, RES-6 bleu azur `#0369A1`, RES-7 rouge
  framboise `#BE123C` et RES-8 vert forêt `#2F7D32` ;
- fonds pastel dérivés à 20 % sur blanc et texte sombre `#1F2937`, avec des
  contrôles de contraste d’au moins 4,5:1 pour le texte, 3:1 entre contour et
  fond pastel et 4,5:1 pour du texte blanc sur la couleur principale ;
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
  lib/main.dart \
  lib/presentation/common/irn_pillar_palette.dart \
  lib/presentation/assessment/assessment_screen.dart \
  test/app_theme_test.dart \
  test/assessment_screen_layout_test.dart \
  test/irn_pillar_palette_test.dart
flutter analyze
flutter test \
  test/app_theme_test.dart \
  test/assessment_screen_layout_test.dart \
  test/irn_pillar_palette_test.dart
flutter test
```

Les tests ciblés contrôlent les trois layouts, la hiérarchie typographique,
l’agrandissement du texte et les contrastes de la palette.
