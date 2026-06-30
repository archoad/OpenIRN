# Patch 123D — Campagnes serveur uniquement

Ce patch poursuit la migration OpenIRN vers un fonctionnement **server-only**.

## Objectif

Les données métier suivantes ne sont plus écrites dans `SharedPreferences` côté client Flutter :

- campagnes ;
- réponses et justifications ;
- affectations de critères ;
- journal d’activité de campagne.

Les classes historiques gardent leur nom (`LocalCampaignRepository`, `LocalAssessmentRepository`, etc.) pour limiter les changements dans les écrans, mais elles deviennent des façades API.

## Fonctionnement

Le client lit l’état courant depuis le dernier snapshot serveur :

```text
GET /sync/pull?tenantId=<tenant>&limit=1
```

Les modifications utilisateur reconstruisent un snapshot complet et le publient côté API :

```text
POST /sync/push
```

Le jeton de session court en mémoire est utilisé automatiquement par `OpenIrnApiClient` quand une session est active. Aucun secret n’est persisté localement.

## Changements serveur

Les endpoints de lecture suivants acceptent maintenant un terminal actif via `X-OpenIRN-Device-Id` :

```text
GET /sync/pull
GET /campaigns
```

Les écritures restent protégées par une session/bearer valide.

## Limites assumées

Le journal de synchronisation local reste présent pour l’instant comme trace technique. Sa suppression sera traitée dans un patch ultérieur.

Les anciens contenus `SharedPreferences` ne sont plus utilisés, mais pas encore purgés automatiquement. Une purge dédiée sera ajoutée plus tard pour nettoyer les installations existantes.
