# Patch 111C — Autoriser un nouveau terminal depuis l'application

## Objectif

Ce patch ajoute le parcours côté nouveau terminal : l'utilisateur ne saisit plus le bearer global. Il saisit uniquement un code d'appairage généré depuis :

```text
Administration → Terminaux autorisés → Autoriser un nouveau terminal
```

Le nouveau terminal consomme ensuite ce code auprès du serveur, reçoit son propre jeton de terminal, sauvegarde la configuration locale et relance la synchronisation globale.

## Fichiers modifiés ou ajoutés

```text
flutter/lib/data/api/openirn_api_client.dart
flutter/lib/presentation/referential/referential_overview_screen.dart
flutter/lib/presentation/sync/device_enrollment_screen.dart
docs/111c_autoriser_nouveau_terminal_flutter.md
```

## Fonctionnement

Sur un terminal déjà autorisé :

```text
Accueil → Administration → Administrer → Terminaux autorisés → Autoriser un nouveau terminal
```

Sur le nouveau terminal :

```text
Accueil → Autoriser ce terminal → Appairer
```

L'écran demande :

- un nom lisible pour le terminal ;
- le code d'appairage ;
- le tenant serveur, en paramètre avancé.

Après validation, l'application :

1. appelle `POST /devices/enrollment/consume` ;
2. récupère le `deviceId` et le jeton propre au terminal ;
3. sauvegarde la configuration locale ;
4. active la synchronisation ;
5. déclenche une récupération initiale du snapshot serveur.

## Sécurité

- le bearer global n'est pas saisi sur le nouveau terminal ;
- le code d'appairage est à usage unique ;
- le code expire côté serveur ;
- le terminal reçoit son propre jeton révocable ;
- la révocation individuelle reste disponible depuis la page `Terminaux autorisés`.

## Limite volontaire de ce patch

Le jeton est encore stocké par le mécanisme local existant de configuration. Le patch 111D pourra durcir ce point en migrant le stockage du jeton vers un stockage sécurisé natif lorsque la dépendance sera validée sur macOS, Windows, iOS, iPadOS et Android.
