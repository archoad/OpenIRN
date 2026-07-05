# Patch 179 — Internationalisation Évaluation / notation

Ce patch poursuit la transition bilingue français / anglais engagée avec les patches 176 à 178.

## Périmètre migré

Le patch migre les principaux libellés de l’écran de notation :

- actions du menu `⋮` d’une campagne ;
- cartouche de contexte de campagne ;
- informations de campagne ;
- statut des affectations ;
- cartouche `Score IRN` ;
- cartouche `Notation par actif` ;
- sous-titres de piliers ;
- portée des critères ;
- libellés et aides de la grille IRN ;
- messages d’absence d’affectation ;
- dialogue de justification.

## Fichiers de traduction

Les clés sont ajoutées dans :

- `flutter/assets/i18n/fr.json`
- `flutter/assets/i18n/en.json`

L’écran conserve les noms saisis par les utilisateurs en l’état : noms de campagnes, SI, fonctions critiques, actifs, critères du référentiel et justifications.

## Notes

Ce patch ne modifie pas le serveur, MariaDB, les campagnes, les calculs de score ni le format des exports. Il ne fait que déplacer les textes visibles du périmètre notation vers le mécanisme i18n JSON.
