# Patch 128 — Sessions serveur dans l’administration

Ce patch ajoute une page **Administration → Sessions serveur**.

## Objectif

Depuis la migration en mode serveur uniquement, OpenIRN utilise des sessions courtes en mémoire côté client.
Le serveur conserve la trace de ces sessions dans SQLite afin de pouvoir :

- visualiser les sessions ouvertes ;
- identifier le profil utilisateur et le terminal associés ;
- distinguer les sessions actives, expirées ou révoquées ;
- révoquer une session active non courante.

## API ajoutée

```text
GET    /auth/sessions?tenantId=archoad&includeInactive=true
DELETE /auth/sessions/{session_id}?tenantId=archoad
```

Ces endpoints nécessitent une authentification API valide : session courte, bearer de transition ou ancien jeton terminal encore accepté pendant la migration.

## Interface Flutter

La page **Administration** contient une nouvelle entrée :

```text
Sessions serveur
```

Elle affiche :

- nombre de sessions actives, expirées et révoquées ;
- utilisateur associé ;
- terminal associé ;
- dates de création, expiration, dernière activité et révocation ;
- badge **Session courante** ;
- action **Révoquer** pour les autres sessions actives.

La session courante ne peut pas être révoquée depuis cette action afin d’éviter de couper la branche sur laquelle l’interface d’administration est assise.
