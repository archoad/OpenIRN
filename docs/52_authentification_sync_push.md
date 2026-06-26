# Patch 057 — Authentification API pour `/sync/push`

Ce patch protège le premier endpoint de synchronisation serveur OpenIRN.

## Principe

- `GET /api/health` reste public pour permettre à l’application de tester la connectivité.
- `POST /api/sync/push` exige maintenant un header HTTP :

```http
Authorization: Bearer <OPENIRN_API_TOKEN>
```

Le token est configuré :

- côté serveur avec la variable d’environnement `OPENIRN_API_TOKEN` ;
- côté application dans l’écran `Synchronisation`.

## Serveur

Le backend FastAPI vérifie :

- présence du token serveur ;
- présence du header `Authorization` ;
- schéma `Bearer` ;
- égalité du token via `hmac.compare_digest`.

Codes de retour :

- `401` : token manquant ;
- `403` : token invalide ;
- `503` : token non configuré côté serveur.

## Client Flutter

L’écran `Synchronisation` ajoute un champ `Token API OpenIRN`.

Le token est stocké localement via `SharedPreferences`. Ce stockage est suffisant pour cette étape de prototype. Une étape ultérieure pourra migrer ce secret vers un stockage sécurisé (`flutter_secure_storage`).

## Déploiement systemd

Générer un token :

```bash
tools/generate_openirn_api_token.sh
```

Créer le fichier d’environnement sur `srv` :

```bash
sudo install -o root -g www-data -m 0640 /dev/null /etc/openirn-api.env
sudo vim /etc/openirn-api.env
```

Contenu attendu :

```env
OPENIRN_API_TOKEN=coller_ici_le_token_genere
```

Puis référencer ce fichier dans `/etc/systemd/system/openirn-api.service` :

```ini
EnvironmentFile=/etc/openirn-api.env
```

Redémarrer :

```bash
sudo systemctl daemon-reload
sudo systemctl restart openirn-api
```

## Tests curl

Sans token :

```bash
curl -i -X POST https://www.archoad.io/api/sync/push \
  -H 'Content-Type: application/json' \
  -d '{"type":"openirn.syncPush"}'
```

Réponse attendue : `401`.

Avec token :

```bash
TOKEN='le_token_configure'
curl -i -X POST https://www.archoad.io/api/sync/push \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"type":"openirn.syncPush","sync":{"tenantId":"test","deviceId":"curl"},"campaigns":[]}'
```

Réponse attendue : `200` avec `status=accepted`.
