# Patch 111A — Socle serveur pour l’enrôlement des terminaux

## Objectif

Ce patch prépare le remplacement progressif du bearer partagé par des jetons propres à chaque terminal.

Il ne modifie pas encore l’interface Flutter. L’application continue donc de fonctionner avec la configuration actuelle, mais le serveur sait maintenant :

- créer une invitation d’enrôlement courte durée ;
- consommer une invitation depuis un nouveau terminal ;
- délivrer un jeton propre au terminal ;
- lister les terminaux autorisés ;
- renommer un terminal ;
- révoquer un terminal ;
- accepter soit le bearer historique, soit un jeton de terminal actif sur les endpoints existants.

## Nouvelles tables SQLite

- `authorized_devices` : terminaux autorisés et jetons hachés ;
- `device_enrollment_codes` : invitations à usage unique, stockées sous forme hachée ;
- `device_audit_log` : journal des opérations liées aux terminaux.

## Nouveaux endpoints

```text
GET    /devices?tenantId=...
POST   /devices/enrollment
POST   /devices/enrollment/consume
POST   /devices/{device_id}/rename
DELETE /devices/{device_id}?tenantId=...
```

## Compatibilité

Le bearer actuel `OPENIRN_API_TOKEN` reste valide. Les jetons de terminaux nouvellement délivrés deviennent également valides pour les endpoints existants.

## Sécurité

- Les jetons de terminal ne sont jamais stockés en clair côté serveur.
- Les codes d’enrôlement ne sont jamais stockés en clair côté serveur.
- Les codes sont à usage unique.
- Les codes expirent par défaut après 10 minutes.
- Les terminaux peuvent être révoqués individuellement.

## Test rapide serveur

Créer une invitation avec le bearer actuel :

```bash
curl -s -X POST "$OPENIRN_API_URL/devices/enrollment" \
  -H "Authorization: Bearer $OPENIRN_API_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"tenantId":"default","createdByUserId":"admin","label":"Test terminal"}' | jq
```

Consommer le code retourné :

```bash
curl -s -X POST "$OPENIRN_API_URL/devices/enrollment/consume" \
  -H 'Content-Type: application/json' \
  -d '{"tenantId":"default","code":"CODE-RETOURNE","deviceName":"iPhone test","platform":"ios"}' | jq
```

Lister les terminaux avec le jeton de terminal retourné :

```bash
curl -s "$OPENIRN_API_URL/devices?tenantId=default" \
  -H "Authorization: Bearer $DEVICE_TOKEN" | jq
```
