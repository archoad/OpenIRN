# 139 — Conformité IRN / scoring officiel prudent

## Objectif

Le patch 139 clarifie la conformité OpenIRN avec le référentiel public aDRI IRN sans inventer de règles de pondération non publiées.

Les sources publiques IRN indiquent :

- un référentiel ouvert autour de 8 piliers `RES-1` à `RES-8` ;
- une cotation de chaque critère en `R` ou `NR` ;
- une approche de cartographie et d'évaluation multicritères pondérée ;
- un scoring de 0 à 100 par dimension.

OpenIRN implémente aujourd'hui le moteur R/NR public et vérifiable :

```text
Score OpenIRN R/NR = R / (R + NR) * 100
```

Les critères `N.C.` sont exclus du score et inclus dans la complétude.

## Clarification méthodologique

Le score n'est plus présenté comme un “score officiel” pondéré. Il est nommé :

```text
Score OpenIRN R/NR
```

Son statut technique est exporté explicitement :

```json
{
  "method": "R / (R + NR) * 100",
  "methodLabel": "Score OpenIRN R/NR",
  "methodStatus": "public_rnr_unweighted",
  "notAnsweredPolicy": "excluded_from_score_included_in_completion",
  "criteriaWeightPolicy": "uniform_per_answered_criterion",
  "globalAggregationPolicy": "all_answered_criteria_same_weight",
  "weightedOfficialMethodImplemented": false,
  "officialWeightedMethodStatus": "not_implemented_no_public_formula_available"
}
```

Cette prudence évite de laisser croire qu'OpenIRN applique une pondération officielle tant que la formule exploitable n'est pas disponible dans les sources publiques.

## Changements serveur

- Chemin GitLab par défaut corrigé vers :

```text
Grille d'évaluation IRN (FR)/xlsx
```

- Fallback GitLab conservé vers les anciens chemins historiques.
- Métadonnées de scoring ajoutées au JSON canonique du référentiel officiel.
- `commitSha` et `blobId` sont séparés :
  - `blobId` reste le marqueur de contenu GitLab utilisé pour détecter les mises à jour ;
  - `commitSha` devient une métadonnée d'audit, remplie si GitLab la retourne.
- Les résumés `/referential/official/status`, `/current` et `/history` exposent la méthode de scoring.
- Les libellés de secours des piliers `RES-7` et `RES-8` sont alignés sur les libellés publics.

## Changements Flutter

- Les écrans d'évaluation affichent `Score OpenIRN R/NR`.
- Le modèle `IrnReferential` lit les métadonnées `scoring` du référentiel serveur.
- Le modèle `IrnSource` distingue `commitSha` et `blobId`.
- Les exports passent en `schemaVersion: 7`.
- Les exports conservent `officialScore` comme alias de compatibilité, mais ajoutent le champ recommandé :

```json
"openIrnRnrScore": 75.0
```

## Tests à lancer

```bash
cd flutter
flutter analyze
flutter test
```

Puis côté API :

```bash
cd server/openirn-api
python3 -m py_compile app/main.py
```

## Note importante

Le patch ne change pas la formule de calcul existante. Il la rend plus explicite, plus auditable et plus honnête méthodologiquement.
