#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

TENANT_RE = re.compile(r"[^a-zA-Z0-9_.-]+")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def safe_segment(value: Any, fallback: str) -> str:
    raw = str(value or "").strip()
    if not raw:
        return fallback
    cleaned = TENANT_RE.sub("_", raw)
    return cleaned[:80] or fallback


def read_json(path: Path) -> Any | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"WARN: unable to read JSON {path}: {exc}")
        return None


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def pretty_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2)


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


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


def role_normalize(value: Any) -> str:
    role = str(value or "reader").strip().lower()
    aliases = {
        "admin": "administrator",
        "administrateur": "administrator",
        "administrator": "administrator",
        "pilote": "campaign_manager",
        "pilote_irn": "campaign_manager",
        "campaignmanager": "campaign_manager",
        "campaign_manager": "campaign_manager",
        "evaluateur": "evaluator",
        "évaluateur": "evaluator",
        "evaluator": "evaluator",
        "validateur": "reviewer",
        "validator": "reviewer",
        "reviewer": "reviewer",
        "lecteur": "reader",
        "reader": "reader",
    }
    return aliases.get(role, "reader")


def sanitize_user(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    user_id = str(raw.get("id") or "").strip()
    if not user_id:
        return None
    created_at = str(raw.get("createdAt") or utc_now())
    updated_at = str(raw.get("updatedAt") or created_at)
    active = raw.get("active")
    return {
        "id": user_id,
        "firstName": str(raw.get("firstName") or "").strip(),
        "lastName": str(raw.get("lastName") or "").strip(),
        "email": str(raw.get("email") or "").strip().lower(),
        "role": role_normalize(raw.get("role") or raw.get("roleLabel")),
        "active": active if isinstance(active, bool) else True,
        "createdAt": created_at,
        "updatedAt": updated_at,
    }


def campaign_record(raw_campaign: dict[str, Any]) -> dict[str, Any]:
    """Return the campaign metadata record from a sync campaign snapshot.

    Flutter sync payloads store each item as:
      {"campaign": {...}, "answers": [...], "assignments": [...]}
    Older/debug payloads may store the campaign fields directly at item root.
    """
    nested = raw_campaign.get("campaign")
    if isinstance(nested, dict):
        return nested
    return raw_campaign


def campaign_updated_at(raw_campaign: dict[str, Any], received_at: str) -> str:
    campaign = campaign_record(raw_campaign)
    for source in (campaign, raw_campaign):
        for key in ("updatedAt", "lastUpdatedAt", "modifiedAt", "createdAt"):
            value = source.get(key)
            if value:
                return str(value)
    return received_at


def campaign_id(raw_campaign: dict[str, Any]) -> str | None:
    campaign = campaign_record(raw_campaign)
    for source in (campaign, raw_campaign):
        for key in ("id", "campaignId"):
            value = str(source.get(key) or "").strip()
            if value:
                return value
    return None


def ensure_tenant(con: sqlite3.Connection, tenant_id: str) -> None:
    now = utc_now()
    con.execute(
        """
        INSERT INTO tenants(id, created_at, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at
        """,
        (tenant_id, now, now),
    )


def apply_schema(con: sqlite3.Connection, schema_path: Path) -> None:
    schema = schema_path.read_text(encoding="utf-8")
    con.executescript(schema)


def import_users_json(con: sqlite3.Connection, data_dir: Path, verbose: bool) -> int:
    imported = 0
    users_root = data_dir / "users"
    if not users_root.exists():
        return 0

    for tenant_dir in sorted(users_root.iterdir()):
        if not tenant_dir.is_dir():
            continue
        tenant_id = safe_segment(tenant_dir.name, "default")
        ensure_tenant(con, tenant_id)

        users_payload = read_json(tenant_dir / "users.json")
        raw_users = users_payload.get("users") if isinstance(users_payload, dict) else []
        if isinstance(raw_users, list):
            for raw_user in raw_users:
                user = sanitize_user(raw_user)
                if not user:
                    continue
                con.execute(
                    """
                    INSERT INTO users(
                        tenant_id, user_id, first_name, last_name, email, role,
                        active, created_at, updated_at, payload_json
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(tenant_id, user_id) DO UPDATE SET
                        first_name = excluded.first_name,
                        last_name = excluded.last_name,
                        email = excluded.email,
                        role = excluded.role,
                        active = excluded.active,
                        updated_at = excluded.updated_at,
                        payload_json = excluded.payload_json
                    """,
                    (
                        tenant_id,
                        user["id"],
                        user["firstName"],
                        user["lastName"],
                        user["email"],
                        user["role"],
                        1 if user["active"] else 0,
                        user["createdAt"],
                        user["updatedAt"],
                        canonical_json(user),
                    ),
                )
                imported += 1

        credentials_payload = read_json(tenant_dir / "credentials.json")
        credential_users = credentials_payload.get("users") if isinstance(credentials_payload, dict) else {}
        if isinstance(credential_users, dict):
            for user_id, credential in credential_users.items():
                if not isinstance(credential, dict):
                    continue
                # Keep credentials only when the user exists. This avoids orphan rows.
                exists = con.execute(
                    "SELECT 1 FROM users WHERE tenant_id = ? AND user_id = ?",
                    (tenant_id, str(user_id)),
                ).fetchone()
                if not exists:
                    continue
                con.execute(
                    """
                    INSERT INTO user_credentials(
                        tenant_id, user_id, algorithm, iterations, salt, pin_hash,
                        requires_change, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(tenant_id, user_id) DO UPDATE SET
                        algorithm = excluded.algorithm,
                        iterations = excluded.iterations,
                        salt = excluded.salt,
                        pin_hash = excluded.pin_hash,
                        requires_change = excluded.requires_change,
                        updated_at = excluded.updated_at
                    """,
                    (
                        tenant_id,
                        str(user_id),
                        str(credential.get("algorithm") or "pbkdf2_sha256"),
                        int(credential.get("iterations") or 200000),
                        str(credential.get("salt") or ""),
                        str(credential.get("pinHash") or ""),
                        1 if credential.get("requiresChange") is True else 0,
                        str(credential.get("updatedAt") or utc_now()),
                    ),
                )

        if verbose:
            print(f"users: tenant={tenant_id} imported={imported}")

    return imported


def import_sync_snapshots(con: sqlite3.Connection, data_dir: Path, verbose: bool) -> tuple[int, int]:
    snapshots_root = data_dir / "sync-push"
    if not snapshots_root.exists():
        return (0, 0)

    snapshot_count = 0
    campaign_revision_count = 0

    for tenant_dir in sorted(snapshots_root.iterdir()):
        if not tenant_dir.is_dir():
            continue
        tenant_id = safe_segment(tenant_dir.name, "default")
        ensure_tenant(con, tenant_id)

        paths = sorted(tenant_dir.glob("*/*.json"))
        envelopes: list[dict[str, Any]] = []
        for path in paths:
            envelope = read_json(path)
            if isinstance(envelope, dict):
                envelopes.append(envelope)
        envelopes.sort(key=lambda item: str(item.get("receivedAt", "")))

        for envelope in envelopes:
            payload = envelope.get("payload")
            if not isinstance(payload, dict):
                continue
            server_sync_id = str(envelope.get("serverSyncId") or "").strip()
            if not server_sync_id:
                continue
            device_id = safe_segment(envelope.get("deviceId"), "unknown-device")
            received_at = str(envelope.get("receivedAt") or utc_now())
            payload_sha256 = str(envelope.get("payloadSha256") or sha256_json(payload))
            campaigns = payload.get("campaigns") if isinstance(payload.get("campaigns"), list) else []
            campaign_count = len(campaigns)

            con.execute(
                """
                INSERT OR IGNORE INTO sync_snapshots(
                    tenant_id, server_sync_id, device_id, received_at,
                    payload_sha256, campaign_count, payload_json, envelope_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    tenant_id,
                    server_sync_id,
                    device_id,
                    received_at,
                    payload_sha256,
                    campaign_count,
                    canonical_json(payload),
                    canonical_json(envelope),
                ),
            )
            snapshot_count += 1

            raw_users = payload.get("users")
            if isinstance(raw_users, list):
                for raw_user in raw_users:
                    user = sanitize_user(raw_user)
                    if user:
                        con.execute(
                            """
                            INSERT INTO users(
                                tenant_id, user_id, first_name, last_name, email,
                                role, active, created_at, updated_at, payload_json
                            )
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            ON CONFLICT(tenant_id, user_id) DO UPDATE SET
                                first_name = excluded.first_name,
                                last_name = excluded.last_name,
                                email = excluded.email,
                                role = excluded.role,
                                active = excluded.active,
                                updated_at = excluded.updated_at,
                                payload_json = excluded.payload_json
                            """,
                            (
                                tenant_id,
                                user["id"],
                                user["firstName"],
                                user["lastName"],
                                user["email"],
                                user["role"],
                                1 if user["active"] else 0,
                                user["createdAt"],
                                user["updatedAt"],
                                canonical_json(user),
                            ),
                        )

            for raw_campaign in campaigns:
                if not isinstance(raw_campaign, dict):
                    continue
                cid = campaign_id(raw_campaign)
                if not cid:
                    continue
                c_hash = sha256_json(raw_campaign)
                updated_at = campaign_updated_at(raw_campaign, received_at)
                existing = con.execute(
                    "SELECT server_revision, payload_sha256, received_at FROM campaign_states WHERE tenant_id = ? AND campaign_id = ?",
                    (tenant_id, cid),
                ).fetchone()
                if existing and existing[1] == c_hash:
                    continue

                conflict_detected = 0
                conflict_reason = None
                next_revision = 1
                if existing:
                    next_revision = int(existing[0]) + 1
                    if parse_dt(existing[2]) > parse_dt(received_at):
                        conflict_detected = 1
                        conflict_reason = "imported_older_received_at_after_newer_state"

                con.execute(
                    """
                    INSERT INTO campaign_revisions(
                        tenant_id, campaign_id, server_revision, server_sync_id,
                        device_id, updated_at, received_at, payload_sha256,
                        payload_json, conflict_policy, conflict_detected, conflict_reason
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'last_write_wins', ?, ?)
                    ON CONFLICT(tenant_id, campaign_id, server_revision) DO NOTHING
                    """,
                    (
                        tenant_id,
                        cid,
                        next_revision,
                        server_sync_id,
                        device_id,
                        updated_at,
                        received_at,
                        c_hash,
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
                        c_hash,
                        canonical_json(raw_campaign),
                    ),
                )
                con.execute(
                    """
                    INSERT INTO sync_events(
                        tenant_id, event_type, server_sync_id, campaign_id,
                        device_id, created_at, payload_json
                    ) VALUES (?, 'campaign_revision_imported', ?, ?, ?, ?, ?)
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
                campaign_revision_count += 1

        if verbose:
            print(f"sync: tenant={tenant_id} snapshots={len(envelopes)}")

    return (snapshot_count, campaign_revision_count)


def main() -> int:
    parser = argparse.ArgumentParser(description="Migrate OpenIRN JSON API storage to SQLite.")
    parser.add_argument("--data-dir", default="/var/lib/openirn-api", help="OpenIRN API data directory")
    parser.add_argument("--db", default=None, help="SQLite database path. Default: <data-dir>/openirn.sqlite3")
    parser.add_argument("--schema", default=None, help="schema.sql path")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    data_dir = Path(args.data_dir)
    db_path = Path(args.db) if args.db else data_dir / "openirn.sqlite3"
    schema_path = Path(args.schema) if args.schema else Path(__file__).resolve().parents[1] / "sql" / "schema.sql"

    db_path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(db_path)
    con.row_factory = sqlite3.Row
    try:
        con.execute("PRAGMA foreign_keys = ON")
        apply_schema(con, schema_path)
        with con:
            imported_users = import_users_json(con, data_dir, args.verbose)
            imported_snapshots, imported_campaign_revisions = import_sync_snapshots(con, data_dir, args.verbose)
        print(json.dumps({
            "status": "ok",
            "database": str(db_path),
            "dataDir": str(data_dir),
            "importedUsers": imported_users,
            "importedSnapshots": imported_snapshots,
            "importedCampaignRevisions": imported_campaign_revisions,
        }, ensure_ascii=False, indent=2))
    finally:
        con.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
