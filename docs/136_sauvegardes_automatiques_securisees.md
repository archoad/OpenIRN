# Patch 136 — sauvegardes automatiques sécurisées

Ce patch renforce le mécanisme de sauvegarde SQLite existant afin qu’il devienne un garde-fou systématique autour des opérations sensibles du serveur OpenIRN.

## Objectifs

- Conserver les sauvegardes SQLite cohérentes sans arrêt de l’API.
- Signer les manifestes de sauvegarde avec HMAC-SHA-256 lorsque `OPENIRN_API_BACKUP_SIGNATURE_SECRET` ou `OPENIRN_API_TOKEN` est configuré.
- Forcer des permissions privées sur le répertoire et les fichiers de sauvegarde.
- Auditer les créations, restaurations et suppressions de sauvegardes dans SQLite.
- Déclencher automatiquement une sauvegarde de protection avant les mutations administratives sensibles.

## Nouvelles protections serveur

Le serveur crée désormais des sauvegardes de protection avant :

- mise à jour ou réinstallation du référentiel officiel ;
- remplacement de la liste centrale des utilisateurs ;
- changement de PIN utilisateur ;
- restauration d’une révision de campagne ;
- restauration complète d’une sauvegarde serveur.

Pour éviter une explosion du nombre de fichiers, les sauvegardes de protection sont dédupliquées par motif pendant une fenêtre configurable.

Variables d’environnement :

```bash
OPENIRN_API_BACKUP_AUTO_ENABLED=true
OPENIRN_API_BACKUP_PROTECTIVE_ENABLED=true
OPENIRN_API_BACKUP_PROTECTIVE_MIN_INTERVAL_MINUTES=30
OPENIRN_API_BACKUP_KEEP=30
OPENIRN_API_BACKUP_SIGNATURE_SECRET="secret-long-dedicated-if-needed"
```

Si `OPENIRN_API_BACKUP_SIGNATURE_SECRET` n’est pas défini, OpenIRN réutilise `OPENIRN_API_TOKEN` pour signer les manifestes de sauvegarde. Les sauvegardes déjà existantes restent restaurables, mais elles apparaissent comme non signées ou non vérifiées dans l’écran de maintenance.

## Fichiers générés

Chaque sauvegarde conserve le triplet suivant :

```text
openirn-YYYYMMDDTHHMMSSZ.sqlite3
openirn-YYYYMMDDTHHMMSSZ.sqlite3.sha256
openirn-YYYYMMDDTHHMMSSZ.sqlite3.json
```

Le manifeste JSON contient maintenant :

- motif de création ;
- acteur déclencheur ;
- indicateur automatique / manuel ;
- intégrité SQLite ;
- SHA-256 ;
- signature HMAC si un secret est disponible ;
- compteurs de tables.

## Journal d’audit

Nouvelle table SQLite :

```sql
backup_audit_log
```

Elle trace :

- `backup.created` ;
- `backup.restored` ;
- `backup.deleted` ;
- `backup.protective_context`.

L’écran **Maintenance serveur** affiche maintenant la configuration de sécurité des sauvegardes, l’état de signature des dernières sauvegardes et le journal des événements.

## Service systemd

Le timer existant reste à 03:15, mais le service est durci :

- `UMask=0077` ;
- `NoNewPrivileges=true` ;
- `PrivateTmp=true` ;
- `ProtectSystem=strict` ;
- écriture limitée à `/var/lib/openirn-api`.

Après application du patch, réinstaller les unités systemd :

```bash
cd ~/Desktop/OpenIRN
sudo cp server/openirn-api/tools/backup_sqlite.py /opt/openirn-api/tools/backup_sqlite.py
sudo cp server/openirn-api/tools/restore_sqlite_backup.py /opt/openirn-api/tools/restore_sqlite_backup.py
sudo chmod +x /opt/openirn-api/tools/backup_sqlite.py /opt/openirn-api/tools/restore_sqlite_backup.py
sudo chown www-data:www-data /opt/openirn-api/tools/backup_sqlite.py /opt/openirn-api/tools/restore_sqlite_backup.py

sudo cp server/openirn-api/systemd/openirn-api-backup.service /etc/systemd/system/openirn-api-backup.service
sudo cp server/openirn-api/systemd/openirn-api-backup.timer /etc/systemd/system/openirn-api-backup.timer
sudo systemctl daemon-reload
sudo systemctl enable --now openirn-api-backup.timer
sudo systemctl restart openirn-api
```

Test manuel :

```bash
sudo systemctl start openirn-api-backup.service
journalctl -u openirn-api-backup.service -n 80 --no-pager
systemctl list-timers openirn-api-backup.timer
```
