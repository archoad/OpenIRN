# Patch 090 — rebuild campaign states after SQLite migration

Patch 089 imported raw `/sync/push` envelopes into `sync_snapshots`, but it only looked for a campaign id at the root of each campaign item.

The Flutter payload actually stores each campaign item as:

```json
{
  "campaign": { "id": "...", "name": "..." },
  "answers": [],
  "assignments": [],
  "activityLog": {}
}
```

Therefore `sync_snapshots` and `users` could be correctly populated while `campaign_states` stayed empty.

Patch 090 adds:

- nested campaign id detection: `campaign.id`;
- nested campaign timestamp detection: `campaign.updatedAt`;
- a safe rebuild script that repopulates `campaign_states` and `campaign_revisions` from already imported `sync_snapshots`.

## Run

```bash
sudo cp server/openirn-api/tools/rebuild_campaign_states_from_sqlite.py /opt/openirn-api/tools/rebuild_campaign_states_from_sqlite.py
sudo cp server/openirn-api/tools/migrate_json_to_sqlite.py /opt/openirn-api/tools/migrate_json_to_sqlite.py
sudo chown www-data:www-data /opt/openirn-api/tools/*.py

sudo -u www-data python3 /opt/openirn-api/tools/rebuild_campaign_states_from_sqlite.py \
  --db /var/lib/openirn-api/openirn.sqlite3 \
  --tenant archoad \
  --verbose
```

## Verify

```bash
sqlite3 /var/lib/openirn-api/openirn.sqlite3 \
  'select tenant_id, count(*) from campaign_states group by tenant_id;'

sqlite3 /var/lib/openirn-api/openirn.sqlite3 \
  'select tenant_id, campaign_id, server_revision, device_id, received_at from campaign_states order by received_at desc;'
```
