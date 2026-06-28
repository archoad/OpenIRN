# Patch 111B — Page Administration / Terminaux autorisés

## Objectif

Ce patch ajoute l’interface Flutter de gestion des terminaux autorisés.

La page est accessible depuis :

```text
Accueil → Administration → Administrer → Terminaux autorisés
```

L’accès à la page Administration reste protégé par un profil `Administrateur` ou `Pilote IRN`.

## Fonctions ajoutées

- liste des terminaux autorisés côté serveur ;
- affichage des terminaux actifs et révoqués ;
- création d’une invitation d’enrôlement à usage unique ;
- affichage du code court d’appairage ;
- copie du code dans le presse-papiers ;
- renommage d’un terminal actif ;
- révocation d’un terminal actif.

## Fichiers modifiés

```text
flutter/lib/domain/models/authorized_device.dart
flutter/lib/data/api/openirn_api_client.dart
flutter/lib/presentation/admin/authorized_devices_screen.dart
flutter/lib/presentation/admin/administration_screen.dart
docs/111b_terminaux_autorises_flutter.md
```

## Remarque

Ce patch ne modifie pas encore l’écran de premier lancement des nouveaux terminaux.

Pour l’instant, le code d’appairage peut être généré depuis un terminal déjà configuré, mais sa consommation côté application Flutter sera ajoutée dans le patch 111C.

Le serveur peut déjà consommer ces codes via l’endpoint :

```text
POST /devices/enrollment/consume
```
