# Patch 156 — Identifiants UUID

Ce patch fait évoluer les identifiants techniques OpenIRN vers des UUID.

## Entités concernées

- espaces de travail ;
- utilisateurs ;
- campagnes.

## Création

Les nouvelles créations utilisent désormais des UUID v4 :

- création d’un espace de travail depuis l’administration ;
- création du Pilote IRN initial d’un nouvel espace ;
- création d’un utilisateur depuis l’annuaire ;
- création locale ou importée d’une campagne.

L’écran de création d’un espace ne demande plus d’identifiant technique : il est généré automatiquement côté serveur.

## Migration serveur

Au démarrage du serveur, la base SQLite est migrée automatiquement :

- les anciens identifiants de tenants sont remplacés par des UUID ;
- les anciens identifiants utilisateurs sont remplacés par des UUID ;
- les anciens identifiants de campagnes sont remplacés par des UUID ;
- les références associées sont mises à jour dans les tables serveur ;
- les payloads JSON stockés sont réécrits lorsque les anciens identifiants y apparaissent.

Une table `id_aliases` conserve les correspondances entre anciens et nouveaux identifiants. Elle permet au serveur d’accepter encore les anciens identifiants reçus par un client qui n’aurait pas encore rafraîchi sa configuration locale.

## Compatibilité

Le nom affiché des espaces ne change pas. Seuls les identifiants techniques changent.

Après migration, il est recommandé d’ouvrir l’écran **Espaces de travail** puis de resélectionner l’espace actif afin que la configuration locale Flutter mémorise le nouvel UUID du tenant.
