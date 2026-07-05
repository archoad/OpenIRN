# Patch 176 — Transition bilingue français / anglais

Ce patch pose l’architecture de traduction de l’interface OpenIRN.

## Principe

- Les textes traduits sont stockés dans des fichiers JSON :
  - `flutter/assets/i18n/fr.json`
  - `flutter/assets/i18n/en.json`
- Chaque entrée utilise un identifiant stable, par exemple `screen.admin.inventory`.
- Le contrôleur `OpenIrnLocalizations` charge la langue active, conserve le choix dans `SharedPreferences` et notifie l’interface.
- L’en-tête commun `OpenIrnAppBar` affiche deux drapeaux `🇫🇷` et `🇬🇧`, à côté de l’indicateur de connexion serveur.
- Le clic sur un drapeau change immédiatement la langue de l’interface.

## Migration progressive

Pour limiter les risques, le patch fournit aussi une aide de transition : les anciens libellés français déjà présents dans le code peuvent être traduits via un index inverse basé sur `fr.json`.

Le modèle cible reste cependant :

```dart
context.tr('screen.admin.inventory')
```

La suite de la migration pourra donc remplacer progressivement les textes restants par des IDs explicites.

## Périmètre migré dans ce patch

- infrastructure i18n JSON ;
- persistance du choix de langue ;
- sélecteur `FR / EN` dans chaque `OpenIrnAppBar` ;
- titres et actions utilisant la barre commune ;
- indicateur de connexion serveur ;
- page “Mode de calcul de la note IRN”.

## Ajouter une langue

1. Ajouter un fichier JSON dans `flutter/assets/i18n/`.
2. Déclarer l’asset dans `pubspec.yaml`.
3. Ajouter la langue dans `OpenIrnLanguage`.
4. Traduire les IDs existants.
