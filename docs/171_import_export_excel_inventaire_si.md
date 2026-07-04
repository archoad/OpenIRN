# Patch 171 — Import/export Excel de l’inventaire SI

## Objectif

Ajouter deux actions sur la page **Fonctions critiques & actifs** afin de faciliter l’alimentation et l’extraction de l’inventaire métier IRN :

- **Importer Excel** ;
- **Exporter Excel**.

Le périmètre reste volontairement limité à l’inventaire : fonctions critiques, systèmes d’information et actifs. Les campagnes, affectations et notes IRN ne sont pas modifiées.

## Format Excel

L’export génère un fichier `.xlsx` contenant les feuilles suivantes :

1. `Instructions`
2. `Fonctions critiques`
3. `Systèmes information`
4. `Actifs`

### Feuille `Fonctions critiques`

Colonnes :

- `ID fonction`
- `Nom fonction`
- `Description fonction`

### Feuille `Systèmes information`

Colonnes :

- `ID SI`
- `ID fonction`
- `Fonction critique`
- `Nom SI`
- `Porteur`
- `Description SI`

### Feuille `Actifs`

Colonnes :

- `ID actif`
- `ID SI`
- `Système information`
- `Nom actif`
- `Type actif`
- `Criticité`
- `Description actif`

## Import

L’import remplace l’inventaire SI de l’espace de travail cible.

Les objets existants suivants sont supprimés puis recréés depuis le fichier :

- fonctions critiques ;
- systèmes d’information ;
- actifs.

Les campagnes et les notes IRN ne sont pas touchées.

Les colonnes d’identifiants peuvent être conservées lors d’un aller-retour export/import. Si elles sont vides, OpenIRN génère de nouveaux identifiants.

## Dépendance serveur

Le serveur utilise `openpyxl` pour produire et lire de vrais fichiers `.xlsx`.

Après déploiement côté serveur :

```bash
cd /opt/openirn-api
source .venv/bin/activate
pip install -r requirements-mariadb.txt
systemctl restart openirn-api
```

## Endpoints ajoutés

- `GET /inventory/export.xlsx?tenantId=...`
- `POST /inventory/import.xlsx?tenantId=...&mode=replace`

Ces endpoints nécessitent les mêmes droits que la gestion de l’inventaire : Administrateur ou Pilote IRN.
