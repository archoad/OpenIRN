# Patch 054 — Endpoint API fixe Archoad

OpenIRN utilise désormais une URL API fixe :

```text
https://www.archoad.io/api
```

L’URL n’est plus saisie dans l’interface utilisateur. Elle reste présente dans la configuration et dans les payloads JSON pour assurer la traçabilité, mais elle est imposée côté application.

## Écran Synchronisation

L’écran `Synchronisation` permet maintenant :

- d’activer/désactiver la synchronisation ;
- de saisir l’identifiant organisation / tenant ;
- de consulter l’identifiant local appareil ;
- de tester la connectivité vers `https://www.archoad.io/api/health` ;
- de générer le payload `/sync/push`.

Le test de connexion distingue :

- API OpenIRN prête : `/health` répond en HTTP 2xx ;
- serveur joignable mais endpoint absent/protégé : HTTP 401, 403, 404 ou autre réponse ;
- serveur injoignable : erreur DNS, TLS, timeout ou réseau.

## Endpoint serveur recommandé

À implémenter côté serveur :

```http
GET /api/health
```

Réponse recommandée :

```json
{
  "status": "ok",
  "application": "OpenIRN API",
  "version": "0.1.0"
}
```

## Plateformes

Le patch ajoute un script `tools/enable_openirn_network_permissions.sh` pour autoriser les connexions sortantes :

- Android : permission `android.permission.INTERNET` dans le manifest principal ;
- macOS : entitlement `com.apple.security.network.client` dans les entitlements debug/release.
