# Patch 144 — Référentiel officiel global multi-tenant

## Objectif

Corriger le modèle multi-tenant du référentiel officiel IRN.

Les tenants cloisonnent les données opérationnelles :

- utilisateurs ;
- campagnes ;
- sessions ;
- terminaux autorisés ;
- journaux tenant.

Le référentiel officiel aDRI/IRN, lui, est une ressource globale de l'instance OpenIRN : il ne doit pas être réinstallé tenant par tenant.

## Changement fonctionnel

`GET /referential/official/current?tenantId=<tenant>` recherche maintenant :

1. un référentiel actif dans le tenant demandé ;
2. sinon, le référentiel actif global de l'instance, avec priorité :
   - tenant demandé ;
   - tenant d'administration solution (`OPENIRN_SOLUTION_ADMIN_TENANT_ID`, par défaut `archoad`) ;
   - tenant permanent `default` ;
   - dernier référentiel actif disponible.

Ainsi, un nouveau tenant sans référentiel local voit automatiquement le référentiel officiel installé sur l'instance.

## API

La réponse `/referential/official/current` ajoute :

```json
{
  "referentialTenantId": "archoad",
  "sharedAcrossTenants": true
}
```

- `tenantId` reste le tenant demandé par le client ;
- `referentialTenantId` indique où le référentiel actif a été trouvé ;
- `sharedAcrossTenants` indique que le référentiel est servi depuis le référentiel global de l'instance.

## Ce que le patch ne change pas

- Aucun partage de campagnes entre tenants ;
- aucun partage d'utilisateurs ordinaires ;
- aucune modification du moteur de scoring ;
- aucune modification de l'appairage terminal.
