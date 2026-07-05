# Patch 187 — Finalisation de la mutation bilingue

Ce patch complète la migration bilingue français / anglais sur les derniers écrans encore majoritairement monolingues.

## Écrans renforcés

- affectation des critères ;
- détail d’un critère du référentiel ;
- écran À propos / licence ;
- journal sécurité ;
- sessions serveur ;
- maintenance serveur ;
- historique / conflits de campagnes.

## Principe retenu

- les nouveaux libellés applicatifs passent par `context.tr(...)` ;
- les libellés hérités encore transmis sous forme de texte français passent par `context.trText(...)` ;
- les fichiers `fr.json` et `en.json` restent strictement alignés ;
- les écrans conservent le français comme langue de référence et l’anglais comme traduction complète.

## Contrôles réalisés

- cohérence JSON FR/EN : même nombre de clés et aucune clé manquante de part ou d’autre ;
- contrôle des appels directs `tr('...')` avec clé littérale : aucune clé manquante détectée ;
- contrôle de structure simple des fichiers Dart modifiés : parenthèses, accolades et crochets équilibrés.

L’environnement de génération ne contient pas les commandes `flutter` / `dart`; l’analyse Flutter devra donc être relancée localement après application de l’overlay.
