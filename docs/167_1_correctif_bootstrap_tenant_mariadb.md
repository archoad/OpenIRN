# Patch 167.1 — Correctif bootstrap tenant MariaDB

## Objectif

Corriger le script serveur `create_bootstrap_enrollment.py` quand il est utilisé
pour créer un code d’enrôlement dans un espace existant.

## Problème corrigé

Le script utilisait un `INSERT ... ON DUPLICATE KEY UPDATE` partiel sur la table
`tenants`. En mode strict MariaDB, cette forme d’instruction doit quand même
fournir les colonnes obligatoires sans valeur par défaut avant d’atteindre la
branche de mise à jour.

Résultat observé :

```text
Field 'description' doesn't have a default value
```

## Correction

Le script vérifie désormais si l’espace existe avant toute insertion.

- si l’espace existe, aucune recréation n’est tentée ;
- si l’espace manque réellement, une ligne complète est créée avec les champs
  obligatoires du schéma MariaDB ;
- l’option `--list-tenant` est acceptée explicitement comme alias de
  `--list-tenants`.

## Validation

```bash
python3 -m py_compile server/openirn-api/tools/create_bootstrap_enrollment.py
```
