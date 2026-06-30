#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import shutil
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


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


def signature_status(backup: Path) -> str:
    meta_path = backup.with_suffix(backup.suffix + ".json")
    if not meta_path.exists():
        return "unsigned"
    try:
        metadata = json.loads(meta_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return "invalid"
    if not isinstance(metadata, dict):
        return "invalid"
    signature = str(metadata.get("signature") or "").strip()
    if not signature:
        return "unsigned"
    expected = backup_metadata_signature(metadata)
    if not expected:
        return "unverified_no_secret"
    return "valid" if hmac.compare_digest(signature, expected) else "invalid"


def validate_db(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(path)
    with sqlite3.connect(path) as con:
        result = con.execute("pragma integrity_check").fetchone()
        if not result or result[0] != "ok":
            raise RuntimeError(f"SQLite integrity_check failed: {result}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Restore an OpenIRN SQLite backup safely.")
    parser.add_argument("backup", help="Path to openirn-YYYYMMDDTHHMMSSZ.sqlite3 backup file.")
    parser.add_argument(
        "--db",
        default=os.environ.get("OPENIRN_API_DB", "/var/lib/openirn-api/openirn.sqlite3"),
        help="Destination OpenIRN SQLite database path.",
    )
    parser.add_argument(
        "--expected-sha256",
        default="",
        help="Optional expected SHA-256 digest. When omitted, a sibling .sha256 file is used if present.",
    )
    parser.add_argument(
        "--require-signature",
        action="store_true",
        help="Refuse restore unless the backup manifest has a valid HMAC signature.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Actually restore. Without this flag the command performs validation only.",
    )
    args = parser.parse_args()

    backup = Path(args.backup).resolve()
    db = Path(args.db).resolve()
    validate_db(backup)

    expected = args.expected_sha256.strip()
    sha_file = backup.with_suffix(backup.suffix + ".sha256")
    if not expected and sha_file.exists():
        expected = sha_file.read_text(encoding="utf-8").split()[0].strip()

    actual = sha256_file(backup)
    if expected and actual.lower() != expected.lower():
        raise RuntimeError(f"SHA-256 mismatch: expected {expected}, got {actual}")

    manifest_signature_status = signature_status(backup)
    if manifest_signature_status == "invalid":
        raise RuntimeError("Backup manifest HMAC signature mismatch")
    if args.require_signature and manifest_signature_status != "valid":
        raise RuntimeError(f"Backup signature is not valid: {manifest_signature_status}")

    if not args.force:
        print("Validation OK. Re-run with --force to restore.")
        print(f"Backup: {backup}")
        print(f"Target: {db}")
        print(f"SHA256: {actual}")
        print(f"Signature: {manifest_signature_status}")
        return 0

    db.parent.mkdir(parents=True, exist_ok=True)
    if db.exists():
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        safety_copy = db.with_name(f"{db.name}.before-restore-{stamp}")
        shutil.copy2(db, safety_copy)
        chmod_private(safety_copy, 0o600)
        print(f"Safety copy written to {safety_copy}", file=sys.stderr)

    # Remove WAL/SHM companions before replacing the main file.
    for companion in [db.with_suffix(db.suffix + "-wal"), db.with_suffix(db.suffix + "-shm")]:
        if companion.exists():
            companion.unlink()
    shutil.copy2(backup, db)
    chmod_private(db, 0o600)
    validate_db(db)
    print(f"Restored {backup} to {db}")
    print(f"Signature: {manifest_signature_status}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
