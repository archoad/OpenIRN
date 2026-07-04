# Patch 168 — Identité globale des terminaux

## Objectif

OpenIRN distingue désormais deux notions :

- **le terminal** : identité globale, stable et unique, portée par `device_id` ;
- **l’autorisation** : association entre un terminal et un espace de travail.

La table `terminals` contient l’identité canonique du terminal : nom, plateforme,
dates de création/mise à jour et dernière activité. La table `authorized_devices`
reste la table d’enrôlement par espace de travail.

## Comportement attendu

- Un terminal peut être enrôlé dans plusieurs espaces de travail.
- Il apparaît une seule fois dans la vue globale des terminaux, avec la liste des
  espaces où il est autorisé.
- L’enrôlement dans un nouvel espace ne modifie jamais le nom d’un terminal déjà
  connu.
- Le champ de nom est verrouillé côté Flutter lorsqu’un `deviceId` local existe
  déjà.
- Le renommage reste possible uniquement via l’action explicite d’administration
  “Renommer”. Ce renommage met à jour l’identité canonique du terminal.

## Schéma MariaDB

Ajout de la table :

```sql
CREATE TABLE terminals (
    device_id VARCHAR(160) NOT NULL,
    name VARCHAR(255) NOT NULL DEFAULT '',
    platform VARCHAR(64) NOT NULL DEFAULT '',
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL,
    last_seen_at VARCHAR(40) NULL,
    PRIMARY KEY (device_id)
);
```

Ajout de `device_id` dans `device_enrollment_requests` afin que les demandes
puissent signaler qu’elles concernent un terminal déjà connu.

## Migration automatique

Au redémarrage de l’API, OpenIRN :

1. crée `terminals` si la table n’existe pas ;
2. ajoute `device_enrollment_requests.device_id` si nécessaire ;
3. alimente `terminals` depuis les lignes existantes de `authorized_devices` ;
4. réaligne les noms existants de `authorized_devices` avec le nom canonique.

La migration est enregistrée en version `168` dans `schema_migrations`.

## Contrôle serveur

Après redémarrage :

```bash
cd /opt/openirn-api
sudo -u www-data env \
  OPENIRN_API_MYSQL_URL="$OPENIRN_API_MYSQL_URL" \
  /opt/openirn-api/.venv/bin/python tools/check_terminal_identity.py
```

Pour inspecter un terminal précis :

```bash
sudo -u www-data env \
  OPENIRN_API_MYSQL_URL="$OPENIRN_API_MYSQL_URL" \
  /opt/openirn-api/.venv/bin/python tools/check_terminal_identity.py --device DEVICE_ID
```

## Isolation

Ce patch ne change pas la règle d’isolation introduite en 167.2 : un terminal
n’est autorisé dans un espace que si une ligne active existe dans
`authorized_devices` pour ce couple `(tenant_id, device_id)`.
