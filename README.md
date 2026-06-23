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

Le référentiel IRN est publié par l’aDRI / Digital Resilience Initiative sous sa propre licence. OpenIRN ne doit pas embarquer directement dans GitHub une copie modifiée ou dérivée du référentiel officiel.

La bonne pratique retenue par le projet est :

1. télécharger le fichier officiel depuis la source aDRI ;
2. l’importer localement ;
3. générer un JSON canonique local ;
4. conserver la source, la version, la licence et le checksum ;
5. ne pas versionner les fichiers générés contenant le référentiel officiel.

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

## Préparer le référentiel local

Depuis la racine du dépôt :

```bash
curl -L \
  -o Questionnaire_IRN_v.1.1.xlsx \
  "https://gitlab.com/digitalresilienceinitiative/adri-irn/-/raw/main/Grille%20d%27%C3%A9valuation%20IRN%20%28FR%29/xlsx/Questionnaire_IRN_v.1.1.xlsx"

python3 -m venv .venv
source .venv/bin/activate
pip install openpyxl

python server/scripts/import_adri_referential.py \
  --input Questionnaire_IRN_v.1.1.xlsx \
  --output canonical_irn_v1_1.json \
  --version v1.1

python server/scripts/validate_adri_referential.py \
  --input canonical_irn_v1_1.json \
  --output validation_referential_report.json

python server/scripts/build_referential_bundle.py \
  --input canonical_irn_v1_1.json \
  --output-dir flutter/assets/referentials
```

Les fichiers générés ne sont pas destinés à être commités dans le dépôt public.

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

Le script vérifie notamment que les fichiers sensibles ou générés ne sont pas présents dans le futur commit.

## Licence du code

Le code OpenIRN est proposé sous licence MIT. Voir [`LICENSE`](LICENSE).

Cette licence ne couvre pas le référentiel officiel IRN, qui reste soumis à sa propre licence et à ses propres conditions d’utilisation.
