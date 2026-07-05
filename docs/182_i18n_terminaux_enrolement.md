# Patch 182 — Internationalisation terminaux & enrôlement

Ce patch poursuit la transition bilingue français / anglais d’OpenIRN.

## Périmètre migré

- écran **Terminaux autorisés** ;
- synthèse des terminaux autorisés ;
- demandes d’enrôlement ;
- dialogues d’approbation, refus, révocation et renommage ;
- génération et affichage d’un code d’appairage ;
- écran **Autoriser ce terminal** ;
- formulaire d’appairage ;
- collage d’une invitation ;
- demande d’autorisation depuis un terminal ;
- retour au choix de l’espace de travail.

## Points conservés

Les libellés métiers saisis par les utilisateurs restent inchangés : noms de terminaux, noms d’espaces de travail, notes et messages serveur.

## Technique

Les textes migrés utilisent les fichiers JSON :

- `flutter/assets/i18n/fr.json`
- `flutter/assets/i18n/en.json`

L’archive est un overlay direct : décompression à la racine du projet avec `unzip -o`.
