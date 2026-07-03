# Patch 162 — Suppression d’un espace de travail

Ce patch ajoute une action réservée au rôle **Administrateur** dans :

```text
Administration → Espaces de travail
```

## Interface

Sous le bouton **Créer un espace**, un bouton rouge **Supprimer un espace** permet de supprimer un espace de travail non permanent.

Le flux utilisateur est volontairement en deux étapes :

1. choix de l’espace à supprimer dans la liste des espaces existants ;
2. confirmation explicite avec le message **Êtes-vous sûr ?**.

L’espace **Défaut** n’est jamais proposé à la suppression.

## Données supprimées

La suppression efface l’espace de travail et les données rattachées par cascade SQLite :

- utilisateurs ;
- codes d’accès ;
- campagnes et révisions ;
- synchronisations ;
- terminaux autorisés ;
- demandes et codes d’enrôlement ;
- sessions API ;
- tentatives d’authentification ;
- journaux et référentiels associés à l’espace supprimé.

Les alias techniques liés à l’espace supprimé sont également nettoyés.

## API

Nouvel endpoint :

```http
DELETE /tenants/{tenant_id}
```

Il est réservé au rôle **Administrateur**. Un Pilote IRN ne peut pas supprimer un espace de travail.

## Protection

Le serveur refuse la suppression de l’espace par défaut, même si l’appel est fait directement à l’API.
