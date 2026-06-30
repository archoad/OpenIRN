# Patch 123A v2 — Session serveur sans secret local

Objectif : abandonner `flutter_secure_storage` et le stockage persistant de secrets côté client.

## Modèle retenu

Le client conserve localement uniquement des métadonnées non sensibles :

- URL API fixe OpenIRN ;
- `tenantId` ;
- `deviceId` ;
- activation de la synchronisation.

Le client ne conserve plus localement :

- bearer global ;
- jeton terminal ;
- jeton de session.

Après authentification d’un utilisateur serveur, l’API délivre un jeton de session court `ost_*`, conservé uniquement en mémoire par l’application. La session disparaît à la fermeture de l’application.

## Changements Flutter

- Suppression de la dépendance `flutter_secure_storage`.
- Ajout de `AppSessionManager`, service mémoire pour le jeton de session courant.
- `LocalSyncConfigurationRepository` revient à `SharedPreferences`, mais uniquement pour les métadonnées publiques du terminal.
- Les anciens secrets de fallback créés par le patch 123A sont purgés.
- L’appairage terminal n’enregistre plus de jeton terminal local.
- La saisie bearer d’urgence reste possible mais n’est conservée qu’en mémoire.

## Changements API

- Ajout de la table `api_sessions`.
- `/auth/verify` vérifie le terminal actif via `deviceId`, valide le code utilisateur, puis crée une session courte.
- Les endpoints protégés acceptent :
  - bearer global historique ;
  - ancien jeton terminal de transition ;
  - nouveau jeton de session `ost_*`.
- `/users` peut être lu par un terminal autorisé sans session afin d’afficher la liste des profils à déverrouiller.

## Sécurité

Le `deviceId` reste un identifiant public, pas une preuve cryptographique. La protection repose désormais sur :

- terminal actif côté serveur ;
- profil utilisateur ;
- code personnel ;
- session courte en mémoire ;
- révocation serveur du terminal.

Les prochaines étapes devront renforcer côté serveur : journal d’authentification, limitation des essais et blocage temporaire après erreurs.
