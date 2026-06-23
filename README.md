# OpenIRN

OpenIRN est une application Flutter open source destinée à explorer le référentiel officiel de l’Indice de Résilience Numérique (IRN) et à réaliser des évaluations locales structurées.

L’objectif du projet est de fournir une application simple, auditable et multi-plateforme pour :

- consulter le référentiel IRN officiel ;
- créer des campagnes locales d’évaluation ;
- coter les critères en `R / NR / N.C.` ;
- documenter les justifications ;
- produire une synthèse et un radar des 8 piliers ;
- exporter/importer une campagne au format JSON ;
- préparer un futur mode synchronisé via API.

## Statut du projet

OpenIRN est actuellement un prototype fonctionnel local-first.

Fonctionnalités déjà disponibles :

- chargement du référentiel IRN depuis un bundle JSON local ;
- affichage des piliers et critères ;
- campagnes locales ;
- informations de campagne : système d’information, description, directeur de projet ;
- notation `R / NR / N.C.` ;
- justifications par critère ;
- scoring global et par pilier ;
- radar des 8 piliers ;
- contrôle qualité ;
- workflow de campagne ;
- journal d’activité local ;
- export/import JSON par presse-papiers et fichier.

Fonctionnalités prévues :

- stockage local SQLite/Drift ;
- multi-utilisateur ;
- synchronisation serveur via API ;
- gestion des droits ;
- import de cartographies SI d’entreprise ;
- exports enrichis.

## Important : référentiel IRN officiel

Le code OpenIRN est distinct du référentiel IRN officiel.

Le référentiel IRN est publié par l’aDRI / Digital Resilience Initiative sous sa propre licence Creative Commons. OpenIRN embarque un bundle JSON runtime du référentiel officiel dans les assets Flutter afin que les builds publiés fonctionnent immédiatement hors ligne.

Le bundle embarqué conserve les métadonnées d’attribution nécessaires :

- source officielle ;
- version ;
- fichier source ;
- licence ;
- checksum SHA-256 ;
- avertissements d’import.

Le dépôt ne versionne pas les fichiers de travail utilisés pour régénérer le bundle (`Questionnaire_IRN_*.xlsx`, `canonical_irn_*.json`, rapports de validation).

Voir aussi : [`NOTICE.md`](NOTICE.md).

## Structure du dépôt

```text
OpenIRN/
├── api/                 # contrats API futurs
├── docs/                # documentation projet
├── flutter/             # application Flutter
├── schemas/             # schémas JSON
├── server/              # scripts d’import et futurs composants serveur
├── tools/               # outils de maintenance projet
├── README.md
├── LICENSE
├── NOTICE.md
├── CONTRIBUTING.md
├── SECURITY.md
└── CODE_OF_CONDUCT.md
```

## Référentiel embarqué

Le bundle JSON du référentiel officiel est versionné dans :

```text
flutter/assets/referentials/adri_irn_v1_1.json
flutter/assets/referentials/manifest.json
```

Ces fichiers sont nécessaires au fonctionnement hors ligne de l’application et sont inclus dans les artefacts de release.

Pour régénérer le bundle depuis le fichier officiel aDRI, voir [`docs/34_referentiel_embarque_assets.md`](docs/34_referentiel_embarque_assets.md).

## Lancer OpenIRN

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

Le script vérifie notamment que les fichiers sensibles ou de travail ne sont pas présents, et que le bundle référentiel embarqué est cohérent.

## Licence du code

Le code OpenIRN est proposé sous licence MIT. Voir [`LICENSE`](LICENSE).

Cette licence ne couvre pas le référentiel officiel IRN, qui reste soumis à sa propre licence et à ses propres conditions d’utilisation.
