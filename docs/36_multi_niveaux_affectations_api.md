# Phase multi-niveaux : utilisateurs, affectations et API

Ce lot introduit le socle local qui servira ensuite à l’authentification serveur et à la synchronisation API.

## Périmètre du patch

Le patch ajoute :

- un annuaire local d’utilisateurs ;
- des rôles applicatifs ;
- l’affectation d’un critère IRN à un utilisateur ;
- l’affichage de l’utilisateur affecté dans l’écran d’évaluation ;
- l’export JSON enrichi avec les utilisateurs locaux et les affectations ;
- un évènement de journal `assignment_changed`.

## Rôles introduits

| Rôle | Usage prévu |
|---|---|
| Administrateur | gestion des utilisateurs, campagnes, affectations |
| Pilote IRN | gestion des campagnes et affectations |
| Évaluateur | saisie des critères qui lui sont affectés |
| Validateur | revue et validation |
| Lecteur | consultation |

Dans cette version, ces rôles sont d’abord modélisés localement. L’écran de connexion et l’application stricte des droits seront ajoutés ensuite.

## Affectations

Une affectation relie :

```text
référentiel + campagne + critère → utilisateur
```

Il n’y a qu’un seul utilisateur affecté par critère dans cette première version. Le modèle pourra évoluer vers plusieurs contributeurs par critère si nécessaire.

## Export JSON

L’export passe en `schemaVersion: 6` et ajoute :

```json
{
  "collaboration": {
    "mode": "local_users_and_assignments",
    "users": [],
    "assignments": []
  }
}
```

## Étape suivante

L’étape suivante consiste à ajouter :

1. un utilisateur actif / session locale ;
2. l’application stricte des droits dans l’interface ;
3. les endpoints API d’authentification et de synchronisation ;
4. une file locale `sync_outbox` pour préparer le mode offline-first.
