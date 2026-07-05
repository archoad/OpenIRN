# Patch 185 — Internationalisation accueil & référentiel

Ce patch poursuit la migration bilingue français / anglais d’OpenIRN.

## Périmètre migré

- écran d’accueil OpenIRN ;
- choix de l’espace de travail ;
- autorisation / appairage du terminal ;
- déverrouillage de session ;
- cartouche de session ouverte ;
- avertissement de référentiel serveur absent ;
- catalogue du référentiel aDRI IRN ;
- recherche dans le référentiel ;
- messages d’erreur principaux du chargement référentiel.

## Hors périmètre

Les données métier saisies ou importées ne sont pas traduites : noms d’espaces, utilisateurs, campagnes, fonctions critiques, SI, actifs, libellés du référentiel et messages serveur dynamiques restent affichés tels qu’ils sont fournis.

## Format

Overlay direct à appliquer à la racine du projet avec `unzip -o`.
