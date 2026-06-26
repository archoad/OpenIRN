# Patch 080 — Authentification utilisateur par code central

Ce patch ajoute une authentification simple au moment d'ouvrir une campagne.

## Flux côté client

1. L'utilisateur clique sur `Ouvrir` une campagne.
2. OpenIRN récupère la base utilisateurs centrale via `/users`.
3. L'utilisateur sélectionne son identité.
4. Si la base centrale est disponible, OpenIRN demande le code personnel.
5. Le code est vérifié par l'API via `/auth/verify`.
6. La campagne s'ouvre avec le rôle associé à l'utilisateur authentifié.

En mode secours local ou si la synchronisation n'est pas configurée, OpenIRN conserve la sélection locale sans code serveur.

## Stockage serveur

Les utilisateurs restent stockés dans :

```text
/var/lib/openirn-api/users/<tenantId>/users.json
```

Les codes personnels sont stockés séparément, sous forme hachée PBKDF2-SHA256 :

```text
/var/lib/openirn-api/users/<tenantId>/credentials.json
```

Les codes ne sont jamais renvoyés par `/users`.

## Code initial

Lorsqu'un utilisateur central n'a pas encore de code, le serveur initialise un code temporaire :

```text
0000
```

Ce code doit être remplacé côté administration API.

## Changer le code d'un utilisateur

```bash
TOKEN='ton_token_api'

curl -s -X POST "https://www.archoad.io/api/users/pin" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "tenantId": "archoad",
    "userId": "USER_ID",
    "pin": "1234"
  }' | jq
```

## Vérifier un code manuellement

```bash
curl -s -X POST "https://www.archoad.io/api/auth/verify" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "tenantId": "archoad",
    "userId": "USER_ID",
    "pin": "1234"
  }' | jq
```

## Limites assumées

Ce patch met en place une authentification applicative légère. Il ne remplace pas encore une vraie gestion d'identité complète avec comptes nominatifs, sessions expirables, rotation de secrets, verrouillage après échecs ou MFA.
