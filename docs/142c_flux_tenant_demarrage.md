# Patch 142C — Flux tenant au démarrage

## Objectif

Corriger le flux multi-tenant côté Flutter :

1. l'application démarre sans tenant sélectionné et sans session ;
2. l'utilisateur choisit d'abord un tenant ;
3. si le terminal est autorisé dans ce tenant, OpenIRN propose les utilisateurs rattachés à ce tenant ;
4. si le terminal n'est pas autorisé, OpenIRN affiche deux cartouches :
   - **Autoriser ce terminal** ;
   - **Retour au choix du tenant**.

Le tenant `default` reste permanent côté serveur, mais il n'est plus imposé automatiquement au lancement de l'application.

## Changements principaux

### Flutter

- `SyncConfiguration.empty()` ne force plus `default`.
- Ajout de `SyncConfiguration.hasSelectedTenant`.
- Ajout de `LocalSyncConfigurationRepository.clearTenantSelection()`.
- Au démarrage de `ReferentialOverviewScreen`, la sélection de tenant est réinitialisée.
- Ajout d'un écran d'accueil logique `Choisir un tenant`.
- Le choix du tenant précède désormais le chargement du référentiel, l'appairage et l'ouverture de session.
- En cas de terminal non enrôlé dans le tenant sélectionné, la page OpenIRN affiche :
  - `Autoriser ce terminal` ;
  - `Retour au choix du tenant`.

### API

- `GET /tenants` devient un endpoint de découverte public limité aux métadonnées des tenants.
- Les endpoints métiers restent cloisonnés par tenant et protégés par terminal/session.

## Sécurité

Le patch ne rend pas les utilisateurs, campagnes, terminaux ou référentiels publics. Il expose uniquement la liste des tenants et leurs métadonnées nécessaires au choix initial dans l'application.

## Validation attendue

- Lancement de l'application : affichage du cartouche **Choisir un tenant**.
- Choix d'un tenant où le terminal est autorisé : affichage de **Déverrouiller OpenIRN** puis des utilisateurs du tenant.
- Choix d'un tenant où le terminal n'est pas autorisé : affichage des deux cartouches **Autoriser ce terminal** et **Retour au choix du tenant**.
- Le bouton retour revient bien au choix du tenant.
