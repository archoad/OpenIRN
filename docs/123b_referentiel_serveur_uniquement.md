# Patch 123B — Référentiel serveur uniquement

Objectif : supprimer l’utilisation du référentiel embarqué dans l’application Flutter et charger le référentiel actif depuis l’API OpenIRN.

## Changements principaux

- `main.dart` utilise désormais `ApiIrnReferentialRepository`.
- Le référentiel n’est plus chargé depuis `flutter/assets/referentials`.
- `pubspec.yaml` ne déclare plus `assets/referentials/` comme asset Flutter.
- Au premier lancement, sans terminal autorisé, l’application n’essaie pas de charger de référentiel local.
- Après appairage, l’application appelle l’API serveur :

```text
GET /referential/official/current?tenantId=...
```

- Si aucun référentiel officiel actif n’est installé sur le serveur, la page d’accueil affiche un message clair et laisse l’accès à l’administration pour installer/recharger le référentiel officiel aDRI.
- Les pages Evaluation et Référentiel ne sont accessibles que si un référentiel serveur valide a été chargé.

## Sécurité

Le serveur accepte la lecture du référentiel officiel courant avec :

- une session API valide ; ou
- un terminal actif identifié par `X-OpenIRN-Device-Id`.

Le référentiel officiel aDRI n’est pas considéré comme un secret, mais l’accès reste limité aux terminaux enrôlés.

## Nettoyage local conseillé

Le patch retire les assets du build Flutter, mais `unzip -o` ne supprime pas les anciens fichiers déjà présents dans le projet local. Après validation, tu peux nettoyer le reliquat local-first :

```bash
cd ~/Desktop/OpenIRN
rm -rf flutter/assets/referentials
```

Ce nettoyage n’est pas obligatoire pour compiler, mais il évite de conserver un ancien référentiel local dans le dépôt.
