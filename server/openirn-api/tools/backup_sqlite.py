#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path


def utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


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
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    source_db = Path(args.db).resolve()
    backup_dir = Path(args.backup_dir).resolve()
    backup_dir.mkdir(parents=True, exist_ok=True)

    validate_source(source_db)

    stamp = utc_stamp()
    backup_db = backup_dir / f"openirn-{stamp}.sqlite3"
    backup_with_vacuum_into(source_db, backup_db)

    # Validate the produced backup too. Better fail loudly than keep a corrupt backup.
    validate_source(backup_db)

    digest = sha256_file(backup_db)
    sha_path = backup_db.with_suffix(backup_db.suffix + ".sha256")
    sha_path.write_text(f"{digest}  {backup_db.name}\n", encoding="utf-8")

    metadata = {
        "type": "openirn.sqliteBackup",
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "sourceDb": str(source_db),
        "backupDb": str(backup_db),
        "sha256": digest,
        "sizeBytes": backup_db.stat().st_size,
        "counts": {},
    }
    for table in [
        "tenants",
        "users",
        "sync_snapshots",
        "campaign_states",
        "campaign_revisions",
        "sync_events",
    ]:
        try:
            metadata["counts"][table] = sqlite_count(backup_db, table)
        except sqlite3.Error:
            metadata["counts"][table] = None

    meta_path = backup_db.with_suffix(backup_db.suffix + ".json")
    meta_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    removed = cleanup_old_backups(backup_dir, args.keep)

    print(json.dumps({**metadata, "removedOldBackups": [p.name for p in removed]}, ensure_ascii=False, indent=2))
    if args.verbose:
        print(f"Backup written to {backup_db}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
