# Synchronisation temps réel stricte via Server-Sent Events

OpenIRN utilise désormais un canal SSE côté API :

```http
GET /sync/events?tenantId=<tenant>
Authorization: Bearer <token>
Accept: text/event-stream
```

Le serveur compare périodiquement le dernier snapshot disponible pour le tenant. Lorsqu'un nouveau `serverSyncId` apparaît, il publie :

```text
event: snapshot
data: { ... latestSnapshot ... }
```

Le client Flutter écoute ce flux lorsqu'une campagne est ouverte. À réception d'un nouvel événement, il appelle le mécanisme existant `pullLatestIfRemoteNewer`, qui :

1. vérifie le statut serveur ;
2. compare le dernier `serverSyncId` au journal local ;
3. récupère le dernier snapshot ;
4. vérifie référentiel/checksum ;
5. remplace la version locale par la version serveur.

Un polling de secours toutes les 60 secondes reste présent pour les cas où iOS, macOS ou un proxy coupe le flux SSE.
