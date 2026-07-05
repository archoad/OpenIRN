# Patch 178 — Internationalisation des campagnes

Ce patch poursuit la transition bilingue français / anglais d’OpenIRN.

## Périmètre

- Écran de liste des campagnes.
- Écran de gestion des campagnes.
- Dialogue de création d’une campagne.
- Dialogue de suppression d’une campagne.
- Libellés de statut de campagne.
- Messages de validation liés au choix d’un système d’information.
- Cartouches et badges de synthèse des campagnes SI / actifs.

## Format

Le patch est une archive overlay directe :

```bash
cd ~/Desktop/openIRN
unzip -o ~/Downloads/openirn_patch_178_i18n_campagnes_overlay.zip
cd flutter
flutter analyze
flutter test
```

Aucun script d’application n’est fourni. Aucun `README.md` racine n’est modifié.

## Notes

Les noms métiers saisis par l’utilisateur restent inchangés : noms de campagnes, systèmes d’information, fonctions critiques, actifs et descriptions.
