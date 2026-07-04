# Patch 163B — Dépréciation du bearer global

## Objectif

Supprimer le bearer global comme mécanisme d’administration OpenIRN, tout en conservant le schéma HTTP standard `Authorization: Bearer` pour les sessions serveur.

## Changements serveur

- Les sessions serveur `ost_…` restent transmises avec `Authorization: Bearer`.
- `OPENIRN_API_TOKEN` est désactivé par défaut.
- Le bearer global legacy ne donne plus de droits d’écriture ni d’administration.
- Une compatibilité de lecture très limitée peut être réactivée explicitement avec :

```env
OPENIRN_LEGACY_GLOBAL_BEARER_ENABLED=true
OPENIRN_API_TOKEN=ancien_secret_uniquement_pour_migration
```

Cette compatibilité ne doit servir qu’à une migration ou à un dépannage court. Elle ne remplace pas une session serveur.

## Sauvegardes

Les signatures HMAC de sauvegarde utilisent uniquement :

```env
OPENIRN_API_BACKUP_SIGNATURE_SECRET=secret_dedie_long
```

`OPENIRN_API_TOKEN` n’est plus utilisé comme secret de signature de secours.

## Enrôlement des terminaux

Les nouveaux codes d’appairage ne dépendent plus de `OPENIRN_API_TOKEN`.

Par compatibilité, le serveur sait encore reconnaître les codes d’appairage déjà émis avec l’ancien secret serveur, mais cela ne réactive pas l’accès API par bearer global.

## Interface et documentation

Les anciens libellés de transition sont remplacés par des libellés plus neutres :

- `Session serveur` ;
- `Jeton terminal serveur` ;
- `Jeton legacy en mémoire`.

## Script supprimé

Le script historique suivant est supprimé :

```text
tools/generate_openirn_api_token.sh
```

Pour générer un secret dédié aux signatures de sauvegarde, utiliser :

```bash
tools/generate_openirn_backup_signature_secret.sh
```
