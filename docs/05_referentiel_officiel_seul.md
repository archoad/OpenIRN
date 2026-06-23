# Lot 003 — MVP centré sur le référentiel officiel aDRI

## Décision de périmètre

À ce stade, l'application ne traite **que le référentiel officiel aDRI**.

Les fichiers Excel internes de l'entreprise, les assets, les systèmes critiques, les campagnes et les évaluations seront intégrés plus tard, dans un module séparé.

Cette décision simplifie fortement le développement initial :

```text
Référentiel officiel aDRI
        ↓
JSON canonique versionné
        ↓
Bundle Flutter local
        ↓
Explorateur de piliers et critères
```

## Objectifs du MVP référentiel

Le premier MVP doit permettre de :

1. importer le fichier officiel `Questionnaire_IRN_v.1.1.xlsx` ;
2. produire un JSON canonique non modifié fonctionnellement ;
3. valider la cohérence du référentiel importé ;
4. embarquer ce référentiel dans l'application Flutter ;
5. afficher les 8 piliers ;
6. afficher les critères par pilier ;
7. afficher la portée des critères ;
8. préparer la future notation R / NR.

## Hors périmètre temporaire

Pour l'instant, on ne développe pas :

- l'import de l'Excel entreprise ;
- la cartographie des systèmes d'information ;
- les assets ;
- les utilisateurs ;
- les campagnes ;
- la synchronisation serveur ;
- le scoring entreprise ;
- les exports COMEX.

Ces éléments reviendront une fois le socle référentiel stabilisé.

## Pipeline cible

```text
curl GitLab aDRI
  → import_adri_referential.py
  → canonical_irn_v1_1.json
  → validate_adri_referential.py
  → validation_referential_report.json
  → build_referential_bundle.py
  → flutter/assets/referentials/adri_irn_v1_1.json
  → flutter/assets/referentials/manifest.json
```

## Commandes recommandées

Depuis la racine du starter kit :

```bash
python server/scripts/import_adri_referential.py \
  --input Questionnaire_IRN_v.1.1.xlsx \
  --output canonical_irn_v1_1.json \
  --version v1.1
```

Puis :

```bash
python server/scripts/validate_adri_referential.py \
  --input canonical_irn_v1_1.json \
  --output validation_referential_report.json
```

Puis :

```bash
python server/scripts/build_referential_bundle.py \
  --input canonical_irn_v1_1.json \
  --output-dir flutter/assets/referentials
```

## Résultat attendu

Avec le fichier officiel `v1.1` actuellement publié, on attend :

```text
pillars=8
criteria=30
```

Si le nombre de critères change dans une future version officielle, le validateur doit le signaler. Ce n'est pas automatiquement une erreur bloquante, mais cela impose une revue fonctionnelle.

## Règle d'or

Le référentiel officiel ne doit pas être modifié dans l'application.

L'application peut l'indexer, l'afficher, l'utiliser comme base de campagne et stocker des métadonnées techniques, mais elle doit conserver :

- la source ;
- la version ;
- le chemin du fichier source ;
- le checksum SHA-256 ;
- la licence ;
- les codes originaux lorsque des normalisations techniques sont nécessaires.
