# Patch 183 — Internationalisation Utilisateurs & espaces de travail

Ce patch poursuit la transition bilingue français / anglais en migrant deux écrans d’administration encore très visibles :

- **Utilisateurs** ;
- **Espaces de travail**.

## Écran Utilisateurs

Les éléments suivants utilisent désormais les fichiers `assets/i18n/fr.json` et `assets/i18n/en.json` :

- titre de page ;
- actions d’en-tête ;
- cartouche d’introduction ;
- source des données utilisateurs ;
- rôles et descriptions de rôles ;
- actions de carte utilisateur ;
- dialogue de création/modification utilisateur ;
- dialogue de suppression utilisateur ;
- dialogue de modification du code utilisateur ;
- validations de formulaire principales.

Les noms, emails et libellés d’espaces saisis par les utilisateurs ne sont pas traduits.

## Écran Espaces de travail

Les éléments suivants utilisent désormais les fichiers de traduction :

- titre de page ;
- cartouche de gestion des espaces ;
- badges de synthèse ;
- actions de création, renommage, sélection et suppression ;
- dialogue de création d’espace ;
- dialogue de renommage ;
- dialogue de suppression ;
- validations de formulaire principales.

Les noms d’espaces et descriptions saisis par les utilisateurs restent inchangés.

## Notes

Le patch ne change ni le backend, ni MariaDB, ni le modèle de données. Il s’agit uniquement d’une migration d’interface Flutter vers le socle i18n JSON.
