# Patch 078 — Authentification de campagne et utilisateurs centraux

Ce patch introduit une première brique d'authentification côté client : au clic sur `Ouvrir` une campagne, OpenIRN demande à l'utilisateur de sélectionner son identité et son profil avant d'accéder à l'écran d'évaluation.

## Base utilisateurs centrale

Le serveur expose désormais :

```http
GET /users?tenantId=archoad
Authorization: Bearer <token>
```

La base est stockée sous :

```text
/var/lib/openirn-api/users/<tenantId>/users.json
```

Elle est alimentée automatiquement à partir des snapshots `/sync/push`, qui contiennent déjà le tableau `users`.

Un endpoint d'administration est aussi disponible pour remplacer toute la base :

```http
POST /users/replace
Authorization: Bearer <token>
Content-Type: application/json

{
  "tenantId": "archoad",
  "users": [ ... ]
}
```

## Comportement client

Au clic sur une campagne :

1. OpenIRN tente de récupérer les utilisateurs centraux via `/users`.
2. Si le serveur répond, cette liste remplace la base locale de référence.
3. L'utilisateur sélectionne son identité.
4. La session locale active est mise à jour.
5. La campagne s'ouvre avec les droits du profil sélectionné.

Si le serveur est indisponible ou si la synchronisation n'est pas configurée, OpenIRN bascule en secours local.
