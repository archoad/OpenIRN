#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def chmod_private(path: Path, mode: int) -> None:
    try:
        path.chmod(mode)
    except OSError:
        pass


def write_private_text(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    chmod_private(path, 0o600)


def sqlite_count(db: Path, table: str) -> int:
    with sqlite3.connect(db) as con:
        return int(con.execute(f"select count(*) from {table}").fetchone()[0])


def validate_source(db: Path) -> None:
    if not db.exists():
        raise FileNotFoundError(f"SQLite database not found: {db}")
    if db.stat().st_size <= 0:
        raise RuntimeError(f"SQLite database is empty: {db}")
    with sqlite3.connect(db) as con:
        result = con.execute("pragma integrity_check").fetchone()
        if not result or result[0] != "ok":
            raise RuntimeError(f"SQLite integrity_check failed: {result}")


def backup_with_vacuum_into(source_db: Path, backup_db: Path) -> None:
    # VACUUM INTO creates a compact consistent copy without copying WAL/SHM files.
    # It requires SQLite >= 3.27, available on modern Debian.
    with sqlite3.connect(source_db) as con:
        con.execute("pragma busy_timeout = 10000")
        con.execute(f"vacuum main into {json.dumps(str(backup_db))}")


def cleanup_old_backups(backup_dir: Path, keep: int) -> list[Path]:
    if keep <= 0:
        return []
    backups = sorted(
        backup_dir.glob("openirn-*.sqlite3"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    removed: list[Path] = []
    for old in backups[keep:]:
        for companion in [old, old.with_suffix(old.suffix + ".sha256"), old.with_suffix(old.suffix + ".json")]:
            if companion.exists():
                companion.unlink()
        removed.append(old)
    return removed


def backup_signing_secret() -> str:
    return (
        os.environ.get("OPENIRN_API_BACKUP_SIGNATURE_SECRET", "").strip()
        or os.environ.get("OPENIRN_API_TOKEN", "").strip()
    )


def backup_signature_payload(metadata: dict[str, Any]) -> dict[str, Any]:
    return {
        key: value
        for key, value in metadata.items()
        if key not in {"signature", "signatureAlgorithm", "signatureStatus"}
    }


def backup_metadata_signature(metadata: dict[str, Any]) -> str:
    secret = backup_signing_secret()
    if not secret:
        return ""
    message = canonical_json(backup_signature_payload(metadata)).encode("utf-8")
    return hmac.new(secret.encode("utf-8"), message, hashlib.sha256).hexdigest()


def record_backup_audit(
    db: Path,
    *,
    tenant_id: str,
    backup_name: str,
    reason: str,
    triggered_by_user_id: str,
    sha256: str,
    size_bytes: int,
    automatic: bool,
    removed_old_backups: list[Path],
) -> None:
    try:
        with sqlite3.connect(db) as con:
            con.execute("pragma busy_timeout = 10000")
            con.execute("pragma foreign_keys = ON")
            con.execute(
                """
                INSERT INTO backup_audit_log(
                    tenant_id, backup_name, event_type, reason,
                    triggered_by_user_id, created_at, sha256,
                    size_bytes, payload_json
                ) VALUES (?, ?, 'backup.created', ?, ?, ?, ?, ?, ?)
                """,
                (
                    tenant_id,
                    backup_name,
                    reason,
                    triggered_by_user_id,
                    utc_iso(),
                    sha256,
                    size_bytes,
                    canonical_json(
                        {
                            "automatic": automatic,
                            "removedOldBackups": [p.name for p in removed_old_backups],
                            "source": "systemd_timer" if automatic else "cli",
                        }
                    ),
                ),
            )
            con.commit()
    except sqlite3.Error as exc:
        print(f"Warning: unable to record backup audit event: {exc}", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a consistent OpenIRN SQLite backup.")
    parser.add_argument(
        "--db",
        default=os.environ.get("OPENIRN_API_DB", "/var/lib/openirn-api/openirn.sqlite3"),
        help="Path to the OpenIRN SQLite database.",
    )
    parser.add_argument(
        "--backup-dir",
        default=os.environ.get("OPENIRN_API_BACKUP_DIR", "/var/lib/openirn-api/backups"),
        help="Directory where backup files are written.",
    )
    parser.add_argument(
        "--keep",
        type=int,
        default=int(os.environ.get("OPENIRN_API_BACKUP_KEEP", "30")),
        help="Number of most recent backups to keep. Use 0 to disable cleanup.",
    )
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("OPENIRN_API_BACKUP_TENANT", "default"),
        help="Tenant id used for the backup audit log.",
    )
    parser.add_argument(
        "--reason",
        default=os.environ.get("OPENIRN_API_BACKUP_REASON", "scheduled_timer"),
        help="Reason stored in the signed backup manifest.",
    )
    parser.add_argument(
        "--triggered-by-user-id",
        default=os.environ.get("OPENIRN_API_BACKUP_TRIGGERED_BY", "systemd"),
        help="User or actor stored in the backup manifest.",
    )
    parser.add_argument("--manual", action="store_true", help="Mark the backup as manual instead of automatic.")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    auto_enabled = os.environ.get("OPENIRN_API_BACKUP_AUTO_ENABLED", "true").strip().lower() not in {
        "0",
        "false",
        "no",
        "off",
    }
    if not args.manual and not auto_enabled:
        print(json.dumps({"status": "disabled", "reason": "OPENIRN_API_BACKUP_AUTO_ENABLED=false"}, indent=2))
        return 0

    source_db = Path(args.db).resolve()
    backup_dir = Path(args.backup_dir).resolve()
    backup_dir.mkdir(parents=True, exist_ok=True)
    chmod_private(backup_dir, 0o700)

    validate_source(source_db)

    stamp = utc_stamp()
    backup_db = backup_dir / f"openirn-{stamp}.sqlite3"
    backup_with_vacuum_into(source_db, backup_db)
    chmod_private(backup_db, 0o600)

    # Validate the produced backup too. Better fail loudly than keep a corrupt backup.
    validate_source(backup_db)

    digest = sha256_file(backup_db)
    sha_path = backup_db.with_suffix(backup_db.suffix + ".sha256")
    write_private_text(sha_path, f"{digest}  {backup_db.name}\n")

    metadata = {
        "type": "openirn.sqliteBackup",
        "formatVersion": 2,
        "createdAt": utc_iso(),
        "sourceDb": str(source_db),
        "backupDb": str(backup_db),
        "backupName": backup_db.name,
        "tenantId": args.tenant_id,
        "reason": args.reason,
        "automatic": not args.manual,
        "triggeredByUserId": args.triggered_by_user_id,
        "sha256": digest,
        "sizeBytes": backup_db.stat().st_size,
        "integrityCheck": "ok",
        "retentionKeep": args.keep,
        "counts": {},
    }
    for table in [
        "tenants",
        "users",
        "sync_snapshots",
        "campaign_states",
        "campaign_revisions",
        "authorized_devices",
        "device_enrollment_codes",
        "official_referentials",
        "official_referential_history",
        "sync_events",
        "backup_audit_log",
    ]:
        try:
            metadata["counts"][table] = sqlite_count(backup_db, table)
        except sqlite3.Error:
            metadata["counts"][table] = None

    signature = backup_metadata_signature(metadata)
    if signature:
        metadata["signatureAlgorithm"] = "hmac-sha256-canonical-json-v1"
        metadata["signature"] = signature
        metadata["signatureStatus"] = "valid"
    else:
        metadata["signatureAlgorithm"] = ""
        metadata["signature"] = ""
        metadata["signatureStatus"] = "unsigned"

    meta_path = backup_db.with_suffix(backup_db.suffix + ".json")
    write_private_text(meta_path, json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")

    removed = cleanup_old_backups(backup_dir, args.keep)
    record_backup_audit(
        source_db,
        tenant_id=args.tenant_id,
        backup_name=backup_db.name,
        reason=args.reason,
        triggered_by_user_id=args.triggered_by_user_id,
        sha256=digest,
        size_bytes=backup_db.stat().st_size,
        automatic=not args.manual,
        removed_old_backups=removed,
    )

    print(json.dumps({**metadata, "name": backup_db.name, "removedOldBackups": [p.name for p in removed]}, ensure_ascii=False, indent=2))
    if args.verbose:
        print(f"Backup written to {backup_db}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
