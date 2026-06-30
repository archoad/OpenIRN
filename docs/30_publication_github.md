# Publication GitHub — OpenIRN

Cette page décrit les contrôles minimaux à effectuer avant de pousser une version publique d’OpenIRN.

## 1. Vérifier la racine du dépôt

La racine attendue reste :

```text
OpenIRN/
├── api/
├── docs/
├── flutter/
├── schemas/
├── server/
├── tools/
├── README.md
├── LICENSE
├── NOTICE.md
├── CONTRIBUTING.md
├── SECURITY.md
├── CODE_OF_CONDUCT.md
└── .gitignore
```

## 2. Nettoyer les artefacts locaux

Avant publication, lancer :

```bash
chmod +x tools/apply_openirn_patch_138a_cleanup.sh
./tools/apply_openirn_patch_138a_cleanup.sh
```

Ce script supprime notamment :

- les métadonnées macOS ;
- les swaps/sauvegardes d’éditeur ;
- le répertoire `.tmp/` ;
- les fichiers de travail issus d’imports locaux.

## 3. Vérifier le contenu publiable

```bash
chmod +x tools/check_open_source_readiness.sh
./tools/check_open_source_readiness.sh
```

Le dépôt public ne doit pas contenir :

- le fichier Excel officiel téléchargé ;
- les fichiers canoniques ou rapports générés localement ;
- des exports JSON de campagnes réelles ;
- des fichiers de travail d’entreprise ;
- des secrets ;
- des fichiers `.DS_Store`, `.swp`, `.swo`, `*~` ou `.tmp`.

## 4. Vérifier Flutter

```bash
cd flutter
flutter analyze
flutter test
cd ..
```

## 5. Vérifier l’API serveur

```bash
cd server/openirn-api
python3 -m py_compile app/main.py tools/backup_sqlite.py tools/restore_sqlite_backup.py
cd ../..
```

## 6. Relire Git avant publication

```bash
git status --short
git diff --stat
```

Relire très attentivement les fichiers ajoutés ou supprimés avant le commit.

## 7. Point juridique

La licence MIT proposée concerne uniquement le code OpenIRN.

Le référentiel IRN officiel reste sous sa propre licence. Il faut conserver une séparation nette entre :

- le code OpenIRN ;
- les scripts d’import ;
- les fichiers officiels téléchargés ;
- les fichiers générés localement ;
- les données de campagne utilisateur ;
- les sauvegardes serveur.
