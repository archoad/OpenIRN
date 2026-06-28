# Patch 099 — sauvegarde et restauration SQLite

OpenIRN stocke désormais l’état serveur dans SQLite. Ce patch ajoute une sauvegarde cohérente de la base sans arrêter l’API.

## Sauvegarde

Le script utilise `VACUUM INTO`, qui crée une copie SQLite compacte et cohérente, même lorsque l’API est active.

```bash
sudo -u www-data /opt/openirn-api/.venv/bin/python /opt/openirn-api/tools/backup_sqlite.py --verbose
```

Sorties produites :

```text
/var/lib/openirn-api/backups/openirn-YYYYMMDDTHHMMSSZ.sqlite3
/var/lib/openirn-api/backups/openirn-YYYYMMDDTHHMMSSZ.sqlite3.sha256
/var/lib/openirn-api/backups/openirn-YYYYMMDDTHHMMSSZ.sqlite3.json
```

Par défaut, les 30 dernières sauvegardes sont conservées.

## Installation systemd

```bash
sudo cp server/openirn-api/tools/backup_sqlite.py /opt/openirn-api/tools/backup_sqlite.py
sudo cp server/openirn-api/tools/restore_sqlite_backup.py /opt/openirn-api/tools/restore_sqlite_backup.py
sudo chmod +x /opt/openirn-api/tools/backup_sqlite.py /opt/openirn-api/tools/restore_sqlite_backup.py
sudo chown www-data:www-data /opt/openirn-api/tools/backup_sqlite.py /opt/openirn-api/tools/restore_sqlite_backup.py

sudo cp server/openirn-api/systemd/openirn-api-backup.service /etc/systemd/system/openirn-api-backup.service
sudo cp server/openirn-api/systemd/openirn-api-backup.timer /etc/systemd/system/openirn-api-backup.timer
sudo systemctl daemon-reload
sudo systemctl enable --now openirn-api-backup.timer
```

Vérification :

```bash
systemctl list-timers openirn-api-backup.timer
systemctl status openirn-api-backup.timer
journalctl -u openirn-api-backup.service -n 100 --no-pager
```

## Restauration

La restauration doit être faite avec l’API arrêtée.

Validation sans restauration :

```bash
sudo /opt/openirn-api/.venv/bin/python /opt/openirn-api/tools/restore_sqlite_backup.py \
  /var/lib/openirn-api/backups/openirn-YYYYMMDDTHHMMSSZ.sqlite3
```

Restauration effective :

```bash
sudo systemctl stop openirn-api
sudo /opt/openirn-api/.venv/bin/python /opt/openirn-api/tools/restore_sqlite_backup.py \
  /var/lib/openirn-api/backups/openirn-YYYYMMDDTHHMMSSZ.sqlite3 \
  --force
sudo chown www-data:www-data /var/lib/openirn-api/openirn.sqlite3
sudo systemctl start openirn-api
```

Le script crée une copie de sécurité de la base existante avant restauration.
