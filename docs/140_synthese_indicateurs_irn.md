# Patch 140 — Indicateurs IRN sur la page Synthèse

## Objectif

Ajouter sur la page **Synthèse** un bloc visuel inspiré de la présentation IRN :

- un carré principal affichant la **note globale sur 100** ;
- à droite, **8 carrés** affichant la **note de chaque pilier** ;
- une **couleur continue du rouge au vert** selon la note ;
- insertion **au-dessus du radar des piliers**.

## Implémentation

Le patch enrichit `flutter/lib/presentation/assessment/assessment_summary_screen.dart` avec :

- `_IrnIndicatorBoardCard` : conteneur principal de la synthèse visuelle ;
- `_GlobalIndicatorTile` : carré de score global ;
- `_PillarIndicatorGrid` : grille des 8 piliers ;
- `_IndicatorTile` : composant visuel partagé ;
- `_scoreTileColor()` : conversion note → couleur ;
- `_scoreTileForegroundColor()` : adaptation de la couleur du texte.

## Règles visuelles

- `null` / score indisponible : fond neutre gris clair ;
- `0` : rouge ;
- `50` : jaune ;
- `100` : vert ;
- le texte bascule automatiquement en foncé ou blanc selon la luminance du fond.

## Responsive

- affichage large : carré global à gauche + grille 4 × 2 à droite ;
- affichage plus étroit : carré global au-dessus + grille responsive en 2 ou 4 colonnes selon la place disponible.

## Remarque

Le patch corrige aussi un doublon local de variable dans `_InterpretationCard` afin de garder un fichier Dart propre.
