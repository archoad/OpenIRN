# Cadrage MVP — Application IRN

## Principe directeur

Le référentiel officiel aDRI est la source de vérité. Les fichiers Excel internes servent uniquement à initialiser les données de cartographie, d'assignation et d'évaluation.

```text
Référentiel officiel aDRI GitLab
        ↓
JSON canonique versionné
        ↓
Campagne IRN entreprise
        ↓
Évaluations, validations, scoring, restitution
```

## MVP fonctionnel

### Lot 1 — Référentiel

- Import du référentiel aDRI.
- Calcul du checksum SHA-256 du fichier source.
- Production d'un JSON canonique.
- Conservation de la version, du commit GitLab et de la licence.

### Lot 2 — Cartographie

- Entités.
- Fonctions métier.
- Systèmes critiques.
- Fonctions techniques.
- Assets.
- Assets harmonisés.

### Lot 3 — Campagne

- Création d'une campagne liée à une version de référentiel.
- Périmètre d'évaluation.
- Statuts : draft, assignment, assessment, review, validated, archived.

### Lot 4 — Assignation

- Assignation des critères aux évaluateurs.
- Gestion des rôles : administrateur, pilote IRN, référent entité, évaluateur, validateur, lecteur.

### Lot 5 — Évaluation

- Saisie R / NR officielle.
- Saisie optionnelle d'un niveau de maturité interne.
- Justification obligatoire.
- Niveau de confiance.
- Soumission et validation.

### Lot 6 — Scoring

- Score par asset.
- Score par système critique.
- Score par pilier.
- Score global IRN.
- Restitution radar et heatmap.

## Décisions de conception

- Une campagne est toujours liée à une version précise du référentiel.
- Le référentiel officiel n'est pas modifiable dans l'application.
- Les adaptations internes sont stockées séparément comme paramètres d'évaluation ou de restitution.
- Les données sont stockées localement et synchronisées par API.
- La résolution de conflits est explicite pour les évaluations soumises ou validées.

