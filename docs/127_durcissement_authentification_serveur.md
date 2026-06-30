# Patch 127 — Durcissement de l'authentification serveur

Ce patch ajoute une protection serveur contre les tentatives répétées de connexion.

## Objectif

OpenIRN fonctionne maintenant sans secret persistant côté client. Le `deviceId` est donc un identifiant public de terminal, pas une preuve cryptographique.

La sécurité de niveau 1 repose sur :

- terminal enrôlé et actif ;
- profil utilisateur serveur ;
- code personnel validé par l'API ;
- session courte conservée uniquement en mémoire ;
- limitation des tentatives côté serveur.

Ce patch ajoute la dernière brique : l'anti-bruteforce.

## Nouveautés serveur

Ajout de la table SQLite :

```sql
CREATE TABLE IF NOT EXISTS auth_attempts (...)
```

Chaque tentative d'authentification est journalisée avec :

- tenant ;
- terminal ;
- utilisateur ;
- adresse IP ;
- succès / échec ;
- raison ;
- horodatage.

## Limites par défaut

Fenêtre de contrôle : 15 minutes.

Pendant cette fenêtre :

- 5 échecs maximum pour un terminal ;
- 5 échecs maximum pour un profil utilisateur ;
- 20 échecs maximum depuis une même adresse IP.

Au-delà, l'API renvoie :

```text
429 Too Many Requests
```

avec un message demandant de réessayer plus tard.

## Variables d'environnement

Les seuils sont configurables :

```bash
OPENIRN_AUTH_ATTEMPT_WINDOW_MINUTES=15
OPENIRN_AUTH_MAX_FAILED_BY_DEVICE=5
OPENIRN_AUTH_MAX_FAILED_BY_USER=5
OPENIRN_AUTH_MAX_FAILED_BY_IP=20
OPENIRN_AUTH_ATTEMPT_RETENTION_DAYS=30
```

Mettre une limite à `0` désactive le contrôle correspondant.

## Journalisation

Les événements suivants sont ajoutés dans `device_audit_log` :

- `auth.failed` ;
- `auth.rate_limited` ;
- `session.created` avec l'adresse IP source.

## Redémarrage

Après application du patch, redémarrer l'API OpenIRN pour créer la table `auth_attempts` au démarrage.
