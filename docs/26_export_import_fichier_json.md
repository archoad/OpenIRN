# Patch 024 — Export/import fichier JSON

Ce patch ajoute l’export et l’import de campagnes OpenIRN sous forme de fichiers `.json`, en complément du copier-coller via presse-papiers.

## Export

Depuis l’écran `Export JSON`, l’utilisateur peut maintenant :

- enregistrer l’export dans un fichier `.json` ;
- copier le JSON dans le presse-papiers comme auparavant.

Le nom de fichier proposé suit le format :

```text
openirn_<campagne>_<version_referentiel>_<timestamp>.json
```

## Import

Depuis l’écran `Importer un JSON OpenIRN`, l’utilisateur peut maintenant :

- ouvrir un fichier `.json` ;
- coller un JSON depuis le presse-papiers ;
- importer la campagne locale.

## Choix technique

Le patch utilise `file_selector`, le plugin Flutter officiel pour les dialogues natifs d’ouverture et de sauvegarde de fichiers.

Le presse-papiers reste disponible comme solution de secours.
