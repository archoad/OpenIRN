# Patch 138A — Nettoyage publication/documentation

Ce patch lance la phase de sanitization post-`v0.5.0` avec un périmètre volontairement conservateur.

## Objectif

Nettoyer les artefacts de travail et renforcer les contrôles de publication sans toucher au code métier Flutter ni à l’API.

## Nettoyages ciblés

Le script historique `tools/apply_openirn_patch_138a_cleanup.sh` supprimait :

- les fichiers `.DS_Store` et `._*` ;
- les swaps/sauvegardes d’éditeur (`*.swp`, `*.swo`, `*~`, `*.bak`) ;
- le fichier parasite `docs/.30_publication_github.md.swp` ;
- le répertoire temporaire `.tmp/`, notamment les fichiers d’import référentiel locaux.

## Garde-fous ajoutés

`.gitignore` ignore maintenant explicitement :

- les fichiers de swap Vim ;
- les sauvegardes temporaires d’éditeur ;
- `.tmp/` et `tmp/` ;
- les métadonnées OS supplémentaires.

`tools/check_open_source_readiness.sh` vérifie désormais les artefacts de travail dans tout le dépôt, et pas seulement à la racine.

## Documentation

Le `README.md` est remis à jour pour refléter l’état `v0.5.0` : application Flutter + API serveur, référentiel officiel installé côté serveur, sessions, permissions, historisation et sauvegardes sécurisées.

Les documents de publication GitHub ont aussi été clarifiés pour éviter de publier accidentellement des fichiers locaux, temporaires ou sensibles.

## Validation

Depuis le nettoyage 163A, le script 138A n’est plus conservé dans le dépôt courant. Utiliser le contrôle de publication actuel :

```bash
./tools/check_open_source_readiness.sh
```
