# Patch 100 — maintenance serveur depuis OpenIRN

Ce patch ajoute une page d’administration pour consulter l’état du backend SQLite, déclencher une sauvegarde manuelle, restaurer une sauvegarde et supprimer les sauvegardes obsolètes depuis l’application.

## API ajoutée

- `GET /maintenance/status`
- `POST /maintenance/backup`
- `POST /maintenance/backups/{backup_name}/restore`
- `DELETE /maintenance/backups/{backup_name}`

Tous les endpoints exigent le Bearer token OpenIRN.

## Accès depuis Flutter

Depuis la page **Campagnes**, le menu `⋮` propose maintenant :

- `Gérer les campagnes`
- `Maintenance serveur`

L’ouverture de la maintenance serveur impose la sélection puis l’authentification d’un compte **Administrateur** ou **Pilote IRN**, avec le même mécanisme que la gestion des campagnes.

## Informations exposées

La page affiche :

- intégrité SQLite (`pragma integrity_check`) ;
- taille de la base, WAL et SHM ;
- compteurs par table ;
- répertoire de sauvegarde ;
- nombre de sauvegardes ;
- dernière sauvegarde ;
- liste des dernières sauvegardes.

## Sauvegarde manuelle

Le bouton `Sauvegarder maintenant` déclenche côté API un `VACUUM INTO`, puis écrit :

- le fichier `.sqlite3` ;
- le fichier `.sha256` ;
- le fichier `.json` de métadonnées.

La sauvegarde systemd quotidienne du patch 099 reste inchangée.

## Restauration

La restauration impose une double confirmation côté Flutter :

1. confirmation du choix de la sauvegarde ;
2. saisie exacte de `RESTAURER`.

Avant de restaurer, le backend crée automatiquement une sauvegarde de sécurité de la base courante. Le fichier demandé est ensuite vérifié par `integrity_check` et, si disponible, par son SHA-256.

## Suppression

La suppression retire le fichier `.sqlite3` et ses compagnons `.sha256` / `.json` quand ils existent. Le backend refuse les noms qui ne correspondent pas à une sauvegarde SQLite OpenIRN locale.
