# Patch 132 — Verrouillage automatique de session

Ce patch ajoute le verrouillage automatique des sessions serveur courtes dans OpenIRN.

## Objectifs

- Fermer automatiquement la session en mémoire à l’expiration serveur.
- Verrouiller automatiquement l’application après inactivité.
- Ramener l’utilisateur à l’accueil lorsque la session est verrouillée.
- Arrêter la synchronisation de fond lorsque la session n’est plus active.
- Révoquer proprement la session serveur lors du verrouillage manuel.

## Comportement côté client

`AppSessionManager` devient observable et gère maintenant :

- le jeton de session en mémoire uniquement ;
- l’identifiant de session serveur ;
- l’heure d’expiration serveur ;
- l’heure de dernière activité ;
- le verrouillage après inactivité ;
- la raison du dernier verrouillage.

L’activité utilisateur est détectée globalement dans `main.dart` via les interactions pointeur. Si l’utilisateur ne fait plus rien pendant la durée d’inactivité autorisée, la session est supprimée de la mémoire, la synchronisation de fond est arrêtée, et l’application revient à l’écran d’accueil.

## Comportement côté serveur

Deux variables d’environnement permettent de piloter les durées :

```bash
OPENIRN_SESSION_TTL_MINUTES=480
OPENIRN_SESSION_IDLE_TIMEOUT_MINUTES=30
```

Par défaut :

- durée maximale de session : 8 heures ;
- verrouillage après inactivité : 30 minutes.

L’API refuse désormais un jeton de session si la durée d’inactivité serveur est dépassée. La session est alors révoquée côté serveur et un événement `session.idle_timeout` est ajouté au journal de sécurité.

## Verrouillage manuel

Le bouton **Verrouiller** de l’accueil appelle maintenant :

```text
DELETE /auth/session/current?tenantId=<tenant>
```

La session courante est donc révoquée côté serveur, puis supprimée de la mémoire client.

## Fichiers modifiés

- `flutter/lib/domain/services/app_session_manager.dart`
- `flutter/lib/main.dart`
- `flutter/lib/data/api/openirn_api_client.dart`
- `flutter/lib/presentation/referential/referential_overview_screen.dart`
- `server/openirn-api/app/main.py`
