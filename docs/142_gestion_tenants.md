# Patch 142 — Gestion des tenants

## Objectif

Introduire une gestion explicite des tenants OpenIRN :

- le tenant `default` est créé au démarrage et marqué permanent ;
- l’administrateur peut créer un tenant depuis la page **Administration** ;
- la création d’un tenant impose la création d’un **Pilote IRN initial** ;
- les utilisateurs et campagnes restent cloisonnés par `tenant_id` côté serveur ;
- à l’ouverture de session, l’utilisateur choisit d’abord le tenant, puis OpenIRN affiche uniquement les utilisateurs actifs rattachés à ce tenant.

## API serveur

Nouveaux endpoints :

```text
GET /tenants?tenantId=<tenant-courant>
POST /tenants
```

`GET /tenants` est accessible depuis un terminal autorisé du tenant courant ou depuis une session serveur valide. Cela permet d’afficher la liste des tenants avant l’ouverture d’une session utilisateur.

`POST /tenants` exige une session administrateur. Le payload attendu contient :

```json
{
  "requesterTenantId": "default",
  "tenantId": "filiale-a",
  "displayName": "Filiale A",
  "description": "Périmètre Filiale A",
  "pilot": {
    "firstName": "Alice",
    "lastName": "Martin",
    "email": "alice.martin@example.org",
    "pin": "1234"
  }
}
```

Lors de la création :

- le tenant est créé ;
- le Pilote IRN initial est créé avec le rôle `campaign_manager` ;
- le terminal courant est autorisé sur le nouveau tenant ;
- l’administrateur courant est recopié dans le nouveau tenant pour éviter de créer un espace impossible à administrer ;
- les credentials PIN de l’administrateur courant sont recopiés dans le nouveau tenant.

## Interface Flutter

Ajouts :

- nouvelle carte **Tenants** dans **Administration** ;
- nouvel écran `TenantManagementScreen` ;
- dialogue de création de tenant ;
- choix du tenant avant la sélection utilisateur lors du déverrouillage ;
- bascule de tenant depuis l’écran Tenants, qui verrouille la session courante et force une nouvelle authentification dans le tenant choisi.

## Cloisonnement

Les tables serveur critiques possèdent déjà `tenant_id` dans leur clé primaire ou leurs index principaux :

- `users` ;
- `user_credentials` ;
- `campaign_states` ;
- `campaign_revisions` ;
- `sync_snapshots` ;
- `api_sessions` ;
- `authorized_devices` ;
- `official_referentials` ;
- `backup_audit_log`.

Le patch ne fusionne donc pas les données : il expose et exploite le cloisonnement déjà présent.
