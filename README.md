# OpenIRN

**OpenIRN** est une solution open source d’exploration, d’administration et d’évaluation de l’Indice de Résilience Numérique (IRN).

La solution combine une application OpenIRN multi-plateforme et une API serveur FastAPI/MariaDB afin de piloter des campagnes IRN, gérer plusieurs espaces de travail, enrôler des terminaux, centraliser le référentiel officiel et conserver un historique auditable des évaluations.

> OpenIRN est un outil applicatif indépendant. Le référentiel IRN officiel reste publié par l’aDRI / Digital Resilience Initiative, sous sa propre licence et ses propres conditions d’utilisation.

## Fonctionnalités

OpenIRN vise à fournir un environnement opérationnel pour conduire des campagnes d’évaluation IRN de manière structurée, traçable et sécurisée.

La solution couvre aujourd’hui :

- la consultation du référentiel IRN officiel ;
- la mise à jour et l’historisation du référentiel officiel côté serveur ;
- la création et la gestion de campagnes d’évaluation ;
- la notation des critères selon la grille IRN intégrée ;
- la justification contextualisée des réponses ;
- la gestion des affectations par critère ;
- la synthèse, le contrôle qualité et l’export des résultats ;
- le journal d’activité des campagnes ;
- l’historique serveur des versions de campagnes et la détection de conflits ;
- la gestion d’un inventaire métier : fonctions critiques, systèmes d’information et actifs ;
- l’import/export Excel de l’inventaire SI ;
- la création de campagnes à partir d’un système d’information ;
- la notation IRN par actif ;
- le calcul d’une maturité consolidée pour un système d’information ;
- la gestion multi-espaces de travail ;
- l’administration des utilisateurs, des rôles et des codes personnels ;
- l’enrôlement, l’autorisation, la révocation et le renommage des terminaux ;
- la consultation des sessions serveur actives ;
- la consultation du journal de sécurité serveur ;
- la maintenance serveur et les sauvegardes MariaDB signées ;
- une interface multilingue français / anglais / espagnol / allemand.

## Architecture générale

OpenIRN est organisé autour de deux composants principaux.

### Application OpenIRN

L’application fournit l’interface utilisateur OpenIRN. Elle est pensée pour fonctionner sur plusieurs plateformes et sert de point d’entrée pour les évaluateurs, pilotes IRN, validateurs, lecteurs et administrateurs.

Elle prend notamment en charge :

- l’accueil applicatif ;
- la sélection de l’espace de travail ;
- le déverrouillage utilisateur ;
- la consultation du référentiel ;
- les campagnes et les évaluations ;
- les synthèses et contrôles qualité ;
- l’inventaire SI ;
- les exports ;
- l’administration ;
- la synchronisation avec le serveur ;
- le stockage sécurisé de la configuration sensible du terminal.

### API serveur

L’API serveur centralise les données partagées et les opérations d’administration. Elle repose sur FastAPI et MariaDB.

Elle couvre notamment :

- les espaces de travail ;
- les utilisateurs et rôles ;
- les sessions serveur ;
- les terminaux autorisés ;
- les demandes d’enrôlement ;
- les campagnes et révisions ;
- les snapshots de synchronisation ;
- l’inventaire SI ;
- le référentiel officiel ;
- les événements de sécurité ;
- les sauvegardes et leur manifeste signé.

MariaDB est le backend transactionnel serveur de référence.

## Fonctionnalités métier

### Référentiel IRN officiel

OpenIRN sépare strictement le code applicatif du référentiel IRN officiel.

L’API serveur peut :

- vérifier le statut du référentiel officiel ;
- importer la version courante ;
- conserver un historique des versions ;
- exposer les métadonnées utiles à l’audit ;
- fournir le référentiel courant aux terminaux autorisés.

Le référentiel officiel n’est pas relicencié par OpenIRN. Sa licence, sa source et ses conditions d’utilisation restent celles publiées par l’aDRI / Digital Resilience Initiative.

### Campagnes d’évaluation

Une campagne OpenIRN permet de conduire une évaluation structurée autour des critères IRN.

OpenIRN prend en charge :

- la création de campagnes ;
- le suivi de l’état d’avancement ;
- la saisie des réponses ;
- les justifications ;
- l’affectation de critères à des évaluateurs ;
- la consultation des critères affectés ;
- les exports JSON ;
- les exports de synthèse ;
- la production et l'export d'éléments statistiques ;
- la conservation d’un journal d’activité ;
- l’historisation serveur des révisions ;
- la restauration contrôlée de révisions de campagne.

### Inventaire SI et notation par actif

OpenIRN intègre un modèle métier permettant de rattacher les évaluations à un système d’information.

Le modèle est structuré ainsi :

```text
Fonction critique
└── Système d’information
    └── Actif
```

Chaque actif peut porter une criticité de 1 à 4. Une campagne créée depuis un système d’information conserve la fonction critique, le SI et la liste des actifs évalués.

La notation peut alors être conduite actif par actif, avec un calcul consolidé de maturité pour le système d’information.

### Scoring et maturité

OpenIRN applique la grille de notation intégrée suivante :

| Niveau | Sens | Valeur |
| --- | --- | ---: |
| N.C. | Non concerné | exclu du score |
| NR | Non résilient | 10/100 |
| Intention | Intention | 25/100 |
| Moyen | Moyen | 50/100 |
| Résultat | Résultat | 95/100 |

OpenIRN calcule une maturité consolidée tenant compte des scores par actif et de la criticité des actifs.

## Sécurité

OpenIRN manipule des informations potentiellement sensibles : cartographie SI, responsables, évaluations, réponses, campagnes et journaux. La sécurité applicative est donc un axe structurant de la solution.

### Principes retenus

- séparation stricte entre terminal enrôlé et session utilisateur ;
- authentification utilisateur par code personnel ;
- sessions serveur courtes, conservées en mémoire côté client ;
- verrouillage automatique après inactivité ;
- révocation serveur de la session lors du verrouillage manuel ;
- politique d’autorisation centralisée par rôle ;
- opérations d’écriture et d’administration réservées aux sessions autorisées ;
- stockage sécurisé de la configuration sensible du terminal ;
- journalisation des événements de sécurité ;
- limitation des tentatives d’authentification ;
- révocation possible des terminaux ;
- sauvegardes MariaDB avec manifeste signé ;
- contrôles de publication et signature des artefacts Android / Windows.

### Rôles applicatifs

La matrice de permissions distingue actuellement :

- **Administrateur** : accès complet aux campagnes, utilisateurs, terminaux, sécurité, référentiel officiel, historique et maintenance ;
- **Pilote IRN** : pilotage métier des campagnes, affectations, inventaire, export, journal et historique ;
- **Évaluateur** : saisie des critères qui lui sont affectés ;
- **Validateur** : consultation, synthèse et contrôle qualité ;
- **Lecteur** : accès en lecture aux campagnes, synthèses et contrôles qualité.

Un administrateur solution peut administrer plusieurs espaces de travail lorsque le serveur est configuré pour ce mode transverse.

### Terminaux et enrôlement

Un terminal possède une identité technique stable. Il peut être autorisé dans plusieurs espaces de travail, sans être dupliqué dans la vue globale d’administration.

L’enrôlement repose sur :

- une demande d’enrôlement ;
- une validation par un rôle autorisé ;
- un terminal actif côté serveur ;
- une session utilisateur pour les opérations sensibles.

Le `deviceId` identifie un terminal, mais ne constitue pas une preuve cryptographique suffisante pour administrer ou écrire des données sensibles.

### Sessions et verrouillage

Les sessions serveur sont courtes et expirent selon deux paramètres :

```env
OPENIRN_SESSION_TTL_MINUTES=480
OPENIRN_SESSION_IDLE_TIMEOUT_MINUTES=30
```

Par défaut, une session dure au maximum huit heures et se verrouille après trente minutes d’inactivité.

### Sauvegardes serveur

Les sauvegardes serveur sont réalisées sous forme de dumps MariaDB. Chaque sauvegarde possède un manifeste et une signature HMAC calculée avec un secret dédié :

```env
OPENIRN_API_BACKUP_SIGNATURE_SECRET=secret_de_signature_des_manifestes
```

La restauration applicative directe a été retirée volontairement. Une restauration MariaDB doit être conduite par une procédure d’administration maîtrisée.

## Internationalisation

L’interface utilisateur est disponible en français, anglais, espagnol et allemand.

Le français reste la langue métier de référence du projet. Les libellés applicatifs sont externalisés dans des fichiers JSON alignés :

```text
flutter/assets/i18n/fr.json
flutter/assets/i18n/en.json
flutter/assets/i18n/es.json
flutter/assets/i18n/de.json
```

La couche Flutter fournit les helpers nécessaires pour traduire les libellés applicatifs et les textes hérités encore transmis sous forme de chaînes métier.

## Publication et artefacts

Le dépôt contient des workflows GitHub Actions pour :

- analyser et tester l’application Flutter ;
- vérifier la préparation open source du dépôt ;
- exécuter un préflight de release ;
- produire des artefacts Android signés ;
- produire des artefacts Windows signés ;
- convertir les guides Markdown français et anglais en PDF ;
- publier les empreintes SHA-256 des artefacts.

Les artefacts signés actuellement visés sont :

- `openirn-android.apk` ;
- `openirn-android.aab` ;
- `openirn-windows-signed.zip` ;
- `openirn-windows-x64.msix` ;
- les huit guides OpenIRN français et anglais au format PDF ;
- `SHA256SUMS.txt`.

macOS et iOS restent présents dans le projet Flutter, mais ne font pas encore partie du profil de release signé principal tant qu’un circuit Apple Developer n’est pas configuré.

## Documentation

- [Installation et initialisation du serveur API](docs/installation-serveur-api.md)
- [Déploiement des applications](docs/deploiement-applications.md)
- [Guide utilisateur par rôle](docs/guide-utilisateur.md)
- [Administration quotidienne d’une instance](docs/administration-instance.md)

English documentation:

- [API server installation and initialization](docs/en/server-api-installation.md)
- [Application deployment](docs/en/application-deployment.md)
- [User guide by role](docs/en/user-guide.md)
- [Day-to-day instance administration](docs/en/instance-administration.md)

Lors d’une release, ces huit sources Markdown sont converties dans `docs/pdf/` puis jointes à la GitHub Release. Le répertoire local `devsteps/`, qui contient l’historique de travail du développement, est volontairement ignoré par Git.

## Structure du dépôt

```text
OpenIRN/
├── api/                 # contrats OpenAPI et brouillons d’API
├── docs/                # guides publics et style de génération PDF
├── flutter/             # application Flutter multi-plateforme
├── server/              # API serveur, SQL, systemd et outils serveur
├── tools/               # outils de contrôle, release et maintenance projet
├── LICENSE
├── NOTICE.md
├── CONTRIBUTING.md
├── SECURITY.md
├── CODE_OF_CONDUCT.md
└── README.md
```

## Démarrage développeur

### Application Flutter

```bash
cd flutter
flutter pub get
flutter analyze
flutter test
flutter run
```

### Contrôles projet

Depuis la racine du dépôt :

```bash
./tools/check_open_source_readiness.sh
./tools/check_release_signing_setup.sh
./tools/check_openirn_release_preflight.sh --tag vX.Y.Z
```

### Backend MariaDB

Le serveur attend une base MariaDB et une URL de connexion :

```env
OPENIRN_API_MYSQL_URL=mysql+pymysql://openirn_runtime:MOT_DE_PASSE@127.0.0.1:3306/openirn?charset=utf8mb4
OPENIRN_API_BACKUP_SIGNATURE_SECRET=SECRET_ALEATOIRE_D_AU_MOINS_32_CARACTERES
```

Le schéma de référence est disponible dans :

```text
server/openirn-api/sql/schema_mariadb.sql
```

Un fichier d’exemple de création de base est disponible dans :

```text
server/openirn-api/sql/create_mariadb_database.example.sql
```

## Licence

Le code OpenIRN est publié sous licence MIT. Voir [`LICENSE`](LICENSE).

Cette licence couvre le code applicatif OpenIRN. Elle ne couvre pas le référentiel IRN officiel, qui reste soumis à sa propre licence et à ses propres conditions d’utilisation.

## Sécurité et signalement

Pour les recommandations de sécurité et le signalement de vulnérabilités, voir [`SECURITY.md`](SECURITY.md).

Ne publiez jamais dans une issue ou une pull request :

- export réel de campagne ;
- cartographie SI interne ;
- fichier Excel métier réel ;
- jeton, secret, certificat ou clé privée ;
- sauvegarde de base de données ;
- donnée personnelle non anonymisée.

## Contribution

Les contributions sont bienvenues. Les principes de contribution sont décrits dans [`CONTRIBUTING.md`](CONTRIBUTING.md).

Avant toute proposition, lancez au minimum :

```bash
./tools/check_open_source_readiness.sh
cd flutter
flutter analyze
flutter test
```
