# Patch 047 — Session locale et premiers droits

Ce patch introduit la notion de **session locale active** dans OpenIRN.

## Objectif

Préparer le passage vers une application multi-niveaux, avant l’authentification serveur :

- l’annuaire local reste la source des utilisateurs ;
- un utilisateur actif est sélectionné localement ;
- son rôle commence à piloter les actions possibles ;
- le modèle pourra ensuite être branché sur une API d’authentification et de synchronisation.

## Utilisateur actif

Le nouvel état est stocké dans `SharedPreferences` :

```text
openirn.localSession.activeUserId
```

Si aucun utilisateur actif n’est défini, OpenIRN sélectionne automatiquement l’administrateur local.

## Droits appliqués dans ce patch

Sur l’écran des campagnes :

| Action | Rôles autorisés |
|---|---|
| Créer une campagne | Administrateur, Pilote IRN |
| Importer une campagne JSON | Administrateur, Pilote IRN |
| Supprimer une campagne | Administrateur, Pilote IRN |
| Passer en prêt pour revue | Administrateur, Pilote IRN |
| Valider une campagne | Administrateur, Pilote IRN, Validateur |
| Archiver / rouvrir | Administrateur, Pilote IRN |
| Consulter | Tous les utilisateurs actifs |

Sur l’écran d’affectation :

| Action | Rôles autorisés |
|---|---|
| Modifier les affectations | Administrateur, Pilote IRN |
| Consulter les affectations | Tous les utilisateurs actifs |

## Limite volontaire

Ce patch ne verrouille pas encore la saisie R / NR critère par critère dans l’écran d’évaluation. Cette étape vient ensuite : un évaluateur ne pourra modifier que les critères qui lui sont affectés.
