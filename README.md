# OpenIRN

OpenIRN est une application Flutter open source destinée à conduire des campagnes d’évaluation autour de l’Indice de Résilience Numérique (IRN), avec une API serveur pour centraliser le référentiel officiel, les campagnes, les utilisateurs, les terminaux et les opérations d’administration.

La version `0.5.0` marque la fin du cycle de sécurisation 130–137 : stockage local verrouillé, sessions serveur, permissions centralisées, autorisation API unifiée, historisation du référentiel officiel, sauvegardes sécurisées et tests d’intégration côté API.

## Fonctionnalités principales

- consultation du référentiel IRN officiel installé côté serveur ;
- création et gestion de campagnes d’évaluation ;
- cotation des critères en `R / NR / N.C.` ;
- justification des réponses ;
- workflow de campagne et journal d’activité ;
- gestion des utilisateurs, rôles et sessions ;
- enrôlement et autorisation des terminaux ;
- synchronisation via API ;
- administration du référentiel officiel ;
- historique des installations du référentiel ;
- sauvegardes serveur sécurisées avec manifeste signé.

## Architecture du dépôt

```text
OpenIRN/
├── api/                 # contrats API et brouillons historiques
├── docs/                # documentation projet et journal des patchs
├── flutter/             # application Flutter multi-plateforme
├── schemas/             # schémas JSON
├── server/              # API OpenIRN et scripts serveur
├── tools/               # outils de maintenance projet
├── README.md
├── LICENSE
├── NOTICE.md
├── CONTRIBUTING.md
├── SECURITY.md
└── CODE_OF_CONDUCT.md
```

## Référentiel IRN officiel

Le code OpenIRN est distinct du référentiel IRN officiel.

Le référentiel IRN est publié par l’aDRI / Digital Resilience Initiative sous sa propre licence Creative Commons. OpenIRN conserve une séparation nette entre :

- le code applicatif ;
- les scripts de chargement et de validation ;
- les fichiers officiels téléchargés ;
- les données de campagne utilisateur ;
- les sauvegardes serveur.

Dans l’architecture actuelle, le référentiel actif est installé et historisé côté serveur. Les fichiers de travail utilisés pour l’import ou la validation ne doivent pas être versionnés dans le dépôt public.

Voir aussi : [`NOTICE.md`](NOTICE.md).

## Lancer l’application Flutter

```bash
cd flutter
flutter pub get
flutter test
flutter run -d macos
```

Autres cibles possibles selon ton environnement Flutter :

```bash
flutter run -d windows
flutter run -d android
flutter run -d ios
```

## Vérification avant publication GitHub

Depuis la racine :

```bash
chmod +x tools/check_open_source_readiness.sh
./tools/check_open_source_readiness.sh
```

Le script vérifie notamment l’absence de fichiers de travail, de fichiers temporaires, de métadonnées macOS, de swaps d’éditeur, d’exports de campagnes et de secrets évidents.

## Licence du code

Le code OpenIRN est proposé sous licence MIT. Voir [`LICENSE`](LICENSE).

Cette licence ne couvre pas le référentiel officiel IRN, qui reste soumis à sa propre licence et à ses propres conditions d’utilisation.
