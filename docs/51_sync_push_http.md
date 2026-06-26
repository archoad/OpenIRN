# Patch 056 — POST `/sync/push`

Ce lot ajoute le premier envoi réel vers le serveur API OpenIRN.

## Côté client Flutter

L’écran **Synchronisation** permet maintenant :

- de tester `GET https://www.archoad.io/api/health` ;
- de préparer le payload local ;
- de copier le payload ;
- d’envoyer le snapshot local vers `POST https://www.archoad.io/api/sync/push`.

Cette première version envoie un **snapshot complet** : référentiel, session active, utilisateurs locaux, campagnes, réponses, justifications, affectations et journal local.

Elle ne gère pas encore :

- authentification distante ;
- `sync/pull` ;
- résolution automatique des conflits ;
- fusion différentielle.

## Côté serveur

Le fichier `server/openirn-api/app/main.py` fournit un exemple FastAPI avec :

- `GET /health` ;
- `POST /sync/push`.

Le endpoint `/sync/push` valide le type `openirn.syncPush`, calcule un SHA-256 et stocke chaque payload reçu dans :

```text
/var/lib/openirn-api/sync-push/<tenantId>/<deviceId>/<serverSyncId>.json
```

## Déploiement serveur

Sur `srv`, après avoir remplacé `/opt/openirn-api/app/main.py` :

```bash
sudo mkdir -p /var/lib/openirn-api
sudo chown -R www-data:www-data /var/lib/openirn-api
sudo systemctl restart openirn-api
sudo journalctl -u openirn-api -f
```

Test manuel :

```bash
curl -s https://www.archoad.io/api/health | jq
```

Puis, après envoi depuis OpenIRN :

```bash
sudo find /var/lib/openirn-api/sync-push -type f -name '*.json' -ls | tail
```

## Prochaine étape

La prochaine étape sera d’ajouter une authentification serveur, probablement avec :

```text
POST /auth/login
Authorization: Bearer <token>
```

Puis de protéger `/sync/push` et `/sync/pull`.
