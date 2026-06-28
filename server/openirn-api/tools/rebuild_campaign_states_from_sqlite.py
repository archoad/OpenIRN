#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def parse_dt(value: Any) -> datetime:
    raw = str(value or "").strip()
    if not raw:
        return datetime.fromtimestamp(0, timezone.utc)
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            return parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except ValueError:
        return datetime.fromtimestamp(0, timezone.utc)


def campaign_record(raw_campaign: dict[str, Any]) -> dict[str, Any]:
    nested = raw_campaign.get("campaign")
    if isinstance(nested, dict):
        return nested
    return raw_campaign


def campaign_id(raw_campaign: dict[str, Any]) -> str | None:
    campaign = campaign_record(raw_campaign)
    for source in (campaign, raw_campaign):
        for key in ("id", "campaignId"):
            value = str(source.get(key) or "").strip()
            if value:
                return value
    return None


def campaign_updated_at(raw_campaign: dict[str, Any], payload: dict[str, Any], received_at: str) -> str:
    campaign = campaign_record(raw_campaign)
    for source in (campaign, raw_campaign, payload):
        for key in ("updatedAt", "lastUpdatedAt", "modifiedAt", "createdAt", "generatedAt"):
            value = source.get(key)
            if value:
                return str(value)
    return received_at


def looks_like_campaign_snapshot(item: Any) -> bool:
    if not isinstance(item, dict):
        return False
    if campaign_id(item):
        return True
    nested = item.get("campaign")
    if isinstance(nested, dict) and campaign_id(nested):
        return True
    return False


def extract_campaigns(payload: dict[str, Any]) -> list[dict[str, Any]]:
    direct = payload.get("campaigns")
    if isinstance(direct, list):
        return [item for item in direct if isinstance(item, dict)]

    # Defensive fallback for future/older envelopes: search recursively for a key named "campaigns".
    found: list[dict[str, Any]] = []

    def walk(value: Any) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                if key == "campaigns" and isinstance(child, list):
                    for item in child:
                        if looks_like_campaign_snapshot(item):
                            found.append(item)
                else:
                    walk(child)
        elif isinstance(value, list):
            for item in value:
                walk(item)

    walk(payload)
    return found


def rebuild(db_path: Path, tenant_filter: str | None, verbose: bool) -> dict[str, Any]:
    con = sqlite3.connect(db_path)
    con.row_factory = sqlite3.Row
    try:
        con.execute("PRAGMA foreign_keys = ON")
        with con:
            if tenant_filter:
                con.execute("DELETE FROM campaign_states WHERE tenant_id = ?", (tenant_filter,))
                con.execute("DELETE FROM campaign_revisions WHERE tenant_id = ?", (tenant_filter,))
                con.execute(
                    "DELETE FROM sync_events WHERE tenant_id = ? AND event_type IN ('campaign_revision_imported','campaign_revision_rebuilt')",
                    (tenant_filter,),
                )
                rows = con.execute(
                    """
                    SELECT tenant_id, server_sync_id, device_id, received_at, payload_json
                    FROM sync_snapshots
                    WHERE tenant_id = ?
                    ORDER BY tenant_id ASC, received_at ASC, server_sync_id ASC
                    """,
                    (tenant_filter,),
                ).fetchall()
            else:
                con.execute("DELETE FROM campaign_states")
                con.execute("DELETE FROM campaign_revisions")
                con.execute(
                    "DELETE FROM sync_events WHERE event_type IN ('campaign_revision_imported','campaign_revision_rebuilt')"
                )
                rows = con.execute(
                    """
                    SELECT tenant_id, server_sync_id, device_id, received_at, payload_json
                    FROM sync_snapshots
                    ORDER BY tenant_id ASC, received_at ASC, server_sync_id ASC
                    """
                ).fetchall()

            snapshot_count = 0
            snapshot_without_campaigns = 0
            revision_count = 0
            skipped_without_id = 0
            campaign_ids: set[str] = set()

            for row in rows:
                snapshot_count += 1
                tenant_id = str(row["tenant_id"])
                server_sync_id = str(row["server_sync_id"])
                device_id = str(row["device_id"] or "unknown-device")
                received_at = str(row["received_at"] or utc_now())
                try:
                    payload = json.loads(str(row["payload_json"] or "{}"))
                except json.JSONDecodeError:
                    if verbose:
                        print(f"WARN: invalid payload_json for {tenant_id}/{server_sync_id}")
                    continue
                if not isinstance(payload, dict):
                    continue

                campaigns = extract_campaigns(payload)
                if not campaigns:
                    snapshot_without_campaigns += 1
                    if verbose:
                        print(f"snapshot without campaigns: tenant={tenant_id} sync={server_sync_id}")
                    continue

                for raw_campaign in campaigns:
                    cid = campaign_id(raw_campaign)
                    if not cid:
                        skipped_without_id += 1
                        if verbose:
                            print(f"campaign without id: tenant={tenant_id} sync={server_sync_id} keys={sorted(raw_campaign.keys())}")
                        continue

                    campaign_ids.add(cid)
                    payload_hash = sha256_json(raw_campaign)
                    updated_at = campaign_updated_at(raw_campaign, payload, received_at)
                    existing = con.execute(
                        """
                        SELECT server_revision, payload_sha256, received_at, device_id
                        FROM campaign_states
                        WHERE tenant_id = ? AND campaign_id = ?
                        """,
                        (tenant_id, cid),
                    ).fetchone()

                    if existing and str(existing["payload_sha256"]) == payload_hash:
                        continue

                    next_revision = int(existing["server_revision"]) + 1 if existing else 1
                    conflict_detected = 0
                    conflict_reason = None
                    if existing:
                        existing_device = str(existing["device_id"] or "")
                        if existing_device and existing_device != device_id:
                            conflict_detected = 1
                            conflict_reason = "different_device_revision_last_write_wins"
                        if parse_dt(existing["received_at"]) > parse_dt(received_at):
                            conflict_detected = 1
                            conflict_reason = "older_snapshot_replayed_after_newer_state"

                    con.execute(
                        """
                        INSERT INTO campaign_revisions(
                            tenant_id, campaign_id, server_revision, server_sync_id,
                            device_id, updated_at, received_at, payload_sha256,
                            payload_json, conflict_policy, conflict_detected, conflict_reason
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'last_write_wins', ?, ?)
                        """,
                        (
                            tenant_id,
                            cid,
                            next_revision,
                            server_sync_id,
                            device_id,
                            updated_at,
                            received_at,
                            payload_hash,
                            canonical_json(raw_campaign),
                            conflict_detected,
                            conflict_reason,
                        ),
                    )
                    con.execute(
                        """
                        INSERT INTO campaign_states(
                            tenant_id, campaign_id, server_revision, server_sync_id,
                            device_id, updated_at, received_at, payload_sha256,
                            payload_json, conflict_policy
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'last_write_wins')
                        ON CONFLICT(tenant_id, campaign_id) DO UPDATE SET
                            server_revision = excluded.server_revision,
                            server_sync_id = excluded.server_sync_id,
                            device_id = excluded.device_id,
                            updated_at = excluded.updated_at,
                            received_at = excluded.received_at,
                            payload_sha256 = excluded.payload_sha256,
                            payload_json = excluded.payload_json,
                            conflict_policy = excluded.conflict_policy
                        """,
                        (
                            tenant_id,
                            cid,
                            next_revision,
                            server_sync_id,
                            device_id,
                            updated_at,
                            received_at,
                            payload_hash,
                            canonical_json(raw_campaign),
                        ),
                    )
                    con.execute(
                        """
                        INSERT INTO sync_events(
                            tenant_id, event_type, server_sync_id, campaign_id,
                            device_id, created_at, payload_json
                        ) VALUES (?, 'campaign_revision_rebuilt', ?, ?, ?, ?, ?)
                        """,
                        (
                            tenant_id,
                            server_sync_id,
                            cid,
                            device_id,
                            utc_now(),
                            canonical_json({
                                "campaignId": cid,
                                "serverRevision": next_revision,
                                "conflictDetected": conflict_detected == 1,
                                "conflictReason": conflict_reason,
                            }),
                        ),
                    )
                    revision_count += 1

            state_count = con.execute(
                "SELECT COUNT(*) FROM campaign_states WHERE tenant_id = COALESCE(?, tenant_id)",
                (tenant_filter,),
            ).fetchone()[0]

        return {
            "status": "ok",
            "database": str(db_path),
            "tenantFilter": tenant_filter,
            "snapshotsRead": snapshot_count,
            "snapshotsWithoutCampaigns": snapshot_without_campaigns,
            "campaignRevisionsInserted": revision_count,
            "campaignStates": state_count,
            "campaignIds": sorted(campaign_ids),
            "campaignsSkippedWithoutId": skipped_without_id,
        }
    finally:
        con.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Rebuild OpenIRN campaign_states and campaign_revisions from SQLite sync_snapshots.")
    parser.add_argument("--db", default="/var/lib/openirn-api/openirn.sqlite3", help="SQLite database path")
    parser.add_argument("--tenant", default=None, help="Optional tenant id to rebuild only one tenant")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    result = rebuild(Path(args.db), args.tenant, args.verbose)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
