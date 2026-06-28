# Patch 120 — Référentiel officiel aDRI côté serveur

Objectif : permettre à OpenIRN de vérifier depuis l’interface d’administration l’existence de la dernière version du référentiel officiel aDRI IRN, de télécharger le fichier `Questionnaire_IRN_v*.xlsx` depuis GitLab, de le convertir en JSON canonique, de le valider puis de l’installer dans la base serveur.

## Interface

Une nouvelle entrée apparaît dans :

```text
Accueil → Administration → Référentiel officiel aDRI
```

La page permet de :

- vérifier la dernière version disponible dans le dépôt public aDRI IRN ;
- comparer cette version avec celle installée sur le serveur ;
- télécharger et installer le référentiel côté serveur.

## API ajoutée

```text
GET  /referential/official/status?tenantId=...
GET  /referential/official/current?tenantId=...
POST /referential/official/update
```

Tous ces endpoints nécessitent l’authentification OpenIRN habituelle : bearer de transition ou jeton terminal.

## Stockage serveur

Le patch ajoute la table SQLite :

```text
official_referentials
```

Le serveur conserve :

- le fichier source XLSX téléchargé ;
- le JSON canonique converti ;
- le rapport de validation ;
- les SHA-256 source et canonique ;
- la version active par tenant.

Par défaut, les fichiers sont stockés dans :

```text
/var/lib/openirn-api/referentials/<tenant>/<referential-id>/
```

Le chemin peut être surchargé avec :

```text
OPENIRN_REFERENTIAL_DIR=/chemin/personnalise
```

## Dépendance Python

L’import du fichier XLSX nécessite `openpyxl` côté serveur :

```bash
pip install openpyxl
```

Si la dépendance est absente, l’API renvoie une erreur explicite lors de la mise à jour du référentiel.

## Variables optionnelles

```text
OPENIRN_ADRI_GITLAB_API=https://gitlab.com/api/v4
OPENIRN_ADRI_PROJECT_PATH=digitalresilienceinitiative/adri-irn
OPENIRN_ADRI_TREE_PATH=Grille d'évaluation IRN (FR)/xlsx
OPENIRN_ADRI_DEFAULT_BRANCH=main
OPENIRN_ADRI_SOURCE_URL=https://gitlab.com/digitalresilienceinitiative/adri-irn
OPENIRN_ADRI_LICENSE=CC BY-NC-ND 4.0
```
