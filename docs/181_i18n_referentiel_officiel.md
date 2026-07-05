# Patch 181 — Internationalisation du référentiel officiel

Ce patch poursuit la transition bilingue français / anglais d’OpenIRN.

## Périmètre

Le patch migre l’écran d’administration **Référentiel officiel aDRI** :

- statut de vérification du référentiel ;
- dialogue de mise à jour / réinstallation ;
- référentiel installé côté serveur ;
- dernière version détectée chez aDRI ;
- historique des imports ;
- actions de vérification et d’installation ;
- libellés de méthode de score.

Les données métier retournées par le serveur, comme les versions, chemins, checksums, commits et identifiants utilisateur, ne sont pas traduites.

## Format

Archive overlay directe :

```bash
cd ~/Desktop/openIRN
unzip -o ~/Downloads/openirn_patch_181_i18n_referentiel_officiel_overlay.zip
cd flutter
flutter analyze
flutter test
```

Aucun changement serveur ou base de données.
