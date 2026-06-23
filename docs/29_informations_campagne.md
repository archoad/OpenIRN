# Patch 027 — Informations de campagne

Ce lot ajoute des informations descriptives obligatoires au niveau de chaque campagne locale.

## Champs ajoutés

Chaque campagne peut désormais porter :

- le nom de la campagne ;
- la description de la campagne ;
- le nom du système d'information concerné ;
- la description du système d'information concerné ;
- le prénom du directeur de projet ;
- le nom du directeur de projet ;
- l'email du directeur de projet.

## Interface

Depuis la liste des campagnes locales :

- la création d'une campagne ouvre un formulaire enrichi ;
- le bouton `Informations` permet de modifier ces champs tant que la campagne n'est pas en lecture seule.

## Contrôle qualité

Le contrôle qualité tient maintenant compte des informations de campagne. Une campagne ne peut passer en `Prêt pour revue` que si :

1. les informations de campagne sont complètes ;
2. tous les critères actifs sont cotés R ou NR ;
3. toutes les réponses R / NR disposent d'une justification.

## Export JSON

L'export JSON passe en `schemaVersion: 5` et ajoute :

```json
{
  "campaign": {
    "system": {
      "name": "SI Facturation",
      "description": "Système critique de facturation."
    },
    "projectDirector": {
      "firstName": "Alice",
      "lastName": "Martin",
      "email": "alice.martin@example.test"
    }
  }
}
```

Les anciens imports restent acceptés : les champs absents sont simplement considérés comme manquants par le contrôle qualité.
