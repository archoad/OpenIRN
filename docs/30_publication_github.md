# Publication GitHub — OpenIRN

Cette étape prépare OpenIRN pour une publication open source propre.

## 1. Vérifier la racine du dépôt

La racine recommandée est :

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

## 2. Vérifier que les fichiers générés ne sont pas commités

```bash
chmod +x tools/check_open_source_readiness.sh
./tools/check_open_source_readiness.sh
```

Le dépôt public ne doit pas contenir :

- le fichier Excel officiel téléchargé ;
- le bundle JSON généré à partir du référentiel officiel ;
- l’Excel d’entreprise ;
- des exports JSON de campagnes réelles ;
- des secrets.

## 3. Vérifier Flutter

```bash
cd flutter
flutter analyze
flutter test
cd ..
```

## 4. Initialiser Git

```bash
git init
git add .
git status
```

Relire très attentivement `git status` avant le premier commit.

## 5. Premier commit

```bash
git commit -m "Initial OpenIRN prototype"
```

## 6. Créer le dépôt GitHub

Créer un dépôt nommé :

```text
OpenIRN
```

Description courte proposée :

```text
Application Flutter open source d’exploration et d’évaluation locale de l’Indice de Résilience Numérique.
```

## 7. Pousser vers GitHub

```bash
git branch -M main
git remote add origin git@github.com:myshelldubois/OpenIRN.git
git push -u origin main
```

Adapter l’URL au nom réel du compte ou de l’organisation GitHub.

## 8. Points juridiques à confirmer

La licence MIT proposée concerne uniquement le code OpenIRN.

Le référentiel IRN officiel reste sous sa propre licence. Il faut conserver une séparation nette entre :

- le code OpenIRN ;
- les scripts d’import ;
- les fichiers officiels téléchargés ;
- les bundles générés localement ;
- les données de campagne utilisateur.
