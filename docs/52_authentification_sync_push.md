# Patch 057 — Authentification API pour `/sync/push`

Ce patch avait introduit la protection du premier endpoint de synchronisation serveur OpenIRN.

## État actuel depuis le patch 163B

Le schéma HTTP reste :

```http
Authorization: Bearer <token>
```

Mais le token attendu n’est plus un bearer global partagé. Les accès d’écriture et d’administration utilisent désormais une session serveur courte (`ost_…`) associée à un utilisateur et à un rôle OpenIRN.

`OPENIRN_API_TOKEN` est déprécié, désactivé par défaut et ne doit plus être utilisé comme secret applicatif principal.

## Principe actuel

- `GET /api/health` reste public pour permettre à l’application de tester la connectivité.
- `POST /api/sync/push` exige une session serveur active avec un rôle autorisé.
- Les sessions sont transmises avec le header standard `Authorization: Bearer`.
- Les anciens jetons de terminal restent limités aux usages de compatibilité explicitement prévus par le serveur.

## Serveur

Le backend FastAPI vérifie :

- présence du header `Authorization` pour les opérations protégées ;
- schéma `Bearer` ;
- validité de la session serveur ;
- rôle utilisateur autorisé pour l’opération demandée ;
- correspondance avec l’espace de travail demandé.

Codes de retour typiques :

- `403` : session expirée, autorisation invalide ou rôle insuffisant ;
- `404` / `409` / `422` selon les contrôles métier de synchronisation.

## Tests curl

Exemple avec une session serveur déjà obtenue :

```bash
SESSION_TOKEN='ost_...'

curl -i -X POST https://www.archoad.io/api/sync/push \
  -H "Authorization: Bearer $SESSION_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"type":"openirn.syncPush","sync":{"tenantId":"default","deviceId":"curl"},"campaigns":[]}'
```

Réponse attendue : `200` avec `status=accepted` si la session et le rôle sont valides.
