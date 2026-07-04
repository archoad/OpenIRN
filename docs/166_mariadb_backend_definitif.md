# Patch 166 — Backend serveur MariaDB définitif

Objectif : finaliser la bascule serveur vers MariaDB et retirer les mécanismes de compatibilité liés à l’ancien stockage serveur.

## Changements

- MariaDB devient le seul backend transactionnel de l’API serveur.
- La configuration runtime ne repose plus sur un choix de backend.
- Les outils de migration historiques sont retirés du dépôt.
- Les sauvegardes serveur utilisent exclusivement des dumps logiques MariaDB.
- La restauration depuis l’application est retirée : une restauration MariaDB doit être réalisée par une procédure DBA contrôlée.
- Les écrans Flutter de maintenance affichent désormais l’état MariaDB.

## Configuration serveur attendue

```env
OPENIRN_API_MYSQL_URL=mysql+pymysql://openirn_api:MOT_DE_PASSE@127.0.0.1:3306/openirn?charset=utf8mb4
OPENIRN_API_BACKUP_SIGNATURE_SECRET=secret_de_signature_des_manifestes
```

La variable de choix de backend peut être supprimée du fichier d’environnement. Elle n’est plus utilisée.

## Contrôle après déploiement

```bash
cd /opt/openirn-api
sudo -u www-data env OPENIRN_API_MYSQL_URL="$OPENIRN_API_MYSQL_URL" \
  /opt/openirn-api/.venv/bin/python tools/check_runtime_backend.py
```

Puis :

```bash
curl -s https://www.archoad.io/openirn-api/health | jq
```

Le champ `storage` doit valoir `mariadb`.
