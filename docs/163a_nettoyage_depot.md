# Patch 163A — Nettoyage dépôt

## Objectif

Ce patch finalise le nettoyage de dépôt avant les évolutions suivantes, sans modifier le comportement d’authentification serveur.

Il ne déprécie pas encore le bearer global : ce point reste volontairement isolé dans le futur patch 163B.

## Suppressions ciblées

Le dépôt ne doit plus contenir :

- le répertoire historique `schemas/` ;
- `tools/check_release_workflow.sh` ;
- `tools/enable_openirn_network_permissions.sh` ;
- `tools/ensure_openirn_network_permissions.sh` ;
- les artefacts locaux de type `.DS_Store`, `__pycache__/`, `.pytest_cache/` ou fichiers Python compilés.

## Documentation

Les références restantes à `schemas/` ont été retirées du `README.md` et de la documentation de publication GitHub.

La documentation de publication ne référence plus le script de nettoyage 138A, qui n’est plus présent dans le dépôt courant. Elle s’appuie désormais sur `tools/check_open_source_readiness.sh` comme contrôle de publication.

## Contrôle de publication

`tools/check_open_source_readiness.sh` vérifie désormais explicitement l’absence :

- du répertoire `schemas/` ;
- de l’ancien script `tools/check_release_workflow.sh` ;
- des anciens scripts réseau `tools/enable_openirn_network_permissions.sh` et `tools/ensure_openirn_network_permissions.sh`.

## Application locale

Depuis la racine du dépôt :

```bash
chmod +x tools/apply_openirn_patch_163a_cleanup.sh
./tools/apply_openirn_patch_163a_cleanup.sh
./tools/check_open_source_readiness.sh
```

Le script est idempotent : il peut être relancé sans risque si certains fichiers ont déjà été supprimés.
