# Patch 151A — Health applicatif sobre

## Objectif

Remplacer le format de `/health` trop calqué sur un cluster Elasticsearch par une réponse applicative simple, stable et utile pour la supervision.

Le endpoint public ne doit pas exposer :

- la liste des routes ;
- le chemin de la base SQLite ;
- les noms des espaces de travail ;
- les utilisateurs ;
- les campagnes ;
- les terminaux ;
- les détails d’erreur internes.

## Nouveau format

`GET /health` renvoie maintenant :

```json
{
  "status": "ok",
  "application": "OpenIRN API",
  "version": "0.10.0",
  "storage": "sqlite",
  "tenantNumber": 3,
  "authRequired": true,
  "authMode": "server_session_with_role_policy",
  "serverTime": "2026-07-02T18:00:00+00:00"
}
```

## Champs calculés

- `tenantNumber` : nombre d’espaces de travail présents dans la table `tenants`.
- `serverTime` : heure UTC du serveur au moment de la réponse.
- `status` :
  - `ok` si la base est disponible et si le nombre d’espaces de travail peut être calculé ;
  - `degraded` si la base est absente ou si le contrôle minimal échoue.

## Sécurité

La lecture SQLite est faite en mode lecture seule. En cas d’erreur, le endpoint renvoie seulement un état `degraded` sans divulguer l’exception ni le chemin de la base.
