#!/usr/bin/env python3
"""Create a one-time OpenIRN device enrollment code directly in SQLite.

This is a break-glass tool for the case where no active terminal can open
Administration -> Terminaux autorisés.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

DEFAULT_DB = Path(os.environ.get("OPENIRN_API_DB", "/var/lib/openirn-api/openirn.sqlite3"))
BOOTSTRAP_PEPPER = "openirn-device-enrollment-bootstrap-v1"
ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
ALLOWED_EXPIRATIONS = {5, 10, 15}


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def normalize_code(value: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", str(value or "").upper())


def format_code(value: str) -> str:
    normalized = normalize_code(value)
    return "-".join(normalized[index : index + 4] for index in range(0, len(normalized), 4))


def new_code() -> str:
    return "".join(secrets.choice(ALPHABET) for _ in range(10))


def code_hash(tenant_id: str, code: str) -> str:
    normalized = normalize_code(code)
    return hmac.new(
        BOOTSTRAP_PEPPER.encode("utf-8"),
        f"{tenant_id}:{normalized}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def ensure_tenant(con: sqlite3.Connection, tenant_id: str) -> None:
    now = utc_now().isoformat()
    con.execute(
        """
        INSERT INTO tenants(id, created_at, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at
        """,
        (tenant_id, now, now),
    )


def count_active_devices(con: sqlite3.Connection, tenant_id: str) -> int:
    row = con.execute(
        """
        SELECT count(*)
        FROM authorized_devices
        WHERE tenant_id = ? AND status = 'active' AND revoked_at IS NULL
        """,
        (tenant_id,),
    ).fetchone()
    return int(row[0] if row else 0)


def record_audit(con: sqlite3.Connection, tenant_id: str, enrollment_id: str, label: str, expires_at: str) -> None:
    try:
        con.execute(
            """
            INSERT INTO device_audit_log(tenant_id, device_id, event_type, created_at, payload_json)
            VALUES (?, NULL, ?, ?, ?)
            """,
            (
                tenant_id,
                "enrollment.bootstrap.created",
                utc_now().isoformat(),
                canonical_json({
                    "enrollmentId": enrollment_id,
                    "label": label,
                    "expiresAt": expires_at,
                    "source": "server-cli",
                }),
            ),
        )
    except sqlite3.Error:
        # The enrollment itself is more important than the audit line in a recovery path.
        pass


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create a temporary OpenIRN enrollment code directly in the server SQLite database.",
    )
    parser.add_argument("--db", default=str(DEFAULT_DB), help="SQLite database path. Default: %(default)s")
    parser.add_argument("--tenant", default="default", help="Tenant id. Default: %(default)s")
    parser.add_argument("--label", default="Bootstrap terminal", help="Invitation label.")
    parser.add_argument(
        "--expires",
        type=int,
        default=10,
        choices=sorted(ALLOWED_EXPIRATIONS),
        help="Code lifetime in minutes. Allowed values: 5, 10, 15.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Create a bootstrap code even if active terminals already exist.",
    )
    args = parser.parse_args()

    db_path = Path(args.db).expanduser()
    tenant_id = normalize_code(args.tenant).lower() if args.tenant else "default"
    if not tenant_id:
        tenant_id = "default"

    if not db_path.exists():
        print(f"ERROR: SQLite database not found: {db_path}", file=sys.stderr)
        print("Start the OpenIRN API once first, or pass --db /path/to/openirn.sqlite3.", file=sys.stderr)
        return 2

    raw_code = new_code()
    display_code = format_code(raw_code)
    normalized_code = normalize_code(raw_code)
    enrollment_id = f"enrollment_{uuid.uuid4().hex}"
    now = utc_now()
    expires_at = (now + timedelta(minutes=args.expires)).isoformat()

    with sqlite3.connect(db_path) as con:
        con.row_factory = sqlite3.Row
        con.execute("PRAGMA foreign_keys = ON")
        ensure_tenant(con, tenant_id)
        active_devices = count_active_devices(con, tenant_id)
        if active_devices > 0 and not args.force:
            print(
                f"ERROR: tenant '{tenant_id}' already has {active_devices} active terminal(s).",
                file=sys.stderr,
            )
            print(
                "Use Administration -> Terminaux autorisés from an active terminal, "
                "or rerun with --force for break-glass recovery.",
                file=sys.stderr,
            )
            return 3

        con.execute(
            """
            INSERT INTO device_enrollment_codes(
                tenant_id, enrollment_id, code_hash, created_by_user_id, label,
                expires_at, consumed_at, consumed_by_device_id, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, ?)
            """,
            (
                tenant_id,
                enrollment_id,
                code_hash(tenant_id, normalized_code),
                "server-bootstrap",
                str(args.label or "Bootstrap terminal")[:120],
                expires_at,
                now.isoformat(),
            ),
        )
        record_audit(con, tenant_id, enrollment_id, str(args.label or "Bootstrap terminal")[:120], expires_at)
        con.commit()

    qr_payload = {
        "type": "openirn.deviceEnrollment",
        "tenantId": tenant_id,
        "code": display_code,
        "enrollmentId": enrollment_id,
        "expiresAt": expires_at,
    }

    print("OpenIRN bootstrap enrollment code")
    print("--------------------------------")
    print(f"Tenant       : {tenant_id}")
    print(f"Database     : {db_path}")
    print(f"Enrollment ID: {enrollment_id}")
    print(f"Expires at   : {expires_at}")
    print(f"Code         : {display_code}")
    print()
    print("Use this code from the OpenIRN home screen: Autoriser ce terminal.")
    print("QR payload JSON:")
    print(canonical_json(qr_payload))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
