#!/usr/bin/env python3
"""Create a one-time OpenIRN device enrollment code directly in MariaDB.

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
import sys
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Iterable
from urllib.parse import parse_qs, unquote, urlparse

ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
ALLOWED_EXPIRATIONS = {5, 10, 15}
ENROLLMENT_CODE_SECRET_ENV = "OPENIRN_ENROLLMENT_CODE_SECRET"


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
    return "".join(secrets.choice(ALPHABET) for _ in range(14))


def enrollment_code_secret() -> str:
    secret = os.environ.get(ENROLLMENT_CODE_SECRET_ENV, "").strip()
    if len(secret) < 32:
        print(
            f"ERROR: {ENROLLMENT_CODE_SECRET_ENV} must contain at least 32 characters.",
            file=sys.stderr,
        )
        raise SystemExit(2)
    return secret


def code_hash(tenant_id: str, code: str, secret: str) -> str:
    normalized = normalize_code(code)
    return hmac.new(
        secret.encode("utf-8"),
        f"{tenant_id}:{normalized}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def tenant_argument(value: str | None) -> str:
    requested = str(value or "").strip()
    return requested or "default"


def import_pymysql() -> Any:
    try:
        import pymysql  # type: ignore
        from pymysql.cursors import DictCursor  # type: ignore
    except ImportError:
        print("ERROR: PyMySQL is missing. Install requirements-mariadb.txt in the server venv.", file=sys.stderr)
        raise SystemExit(1)
    return pymysql, DictCursor


def parse_mysql_url(raw: str) -> dict[str, Any]:
    if not raw:
        print("ERROR: OPENIRN_API_MYSQL_URL is required.", file=sys.stderr)
        raise SystemExit(2)
    parsed = urlparse(raw)
    if parsed.scheme not in {"mysql", "mysql+pymysql", "mariadb", "mariadb+pymysql"}:
        print("ERROR: MariaDB URL must use mysql+pymysql:// or mariadb+pymysql://", file=sys.stderr)
        raise SystemExit(2)
    query = parse_qs(parsed.query)
    database = parsed.path.lstrip("/")
    if not database:
        print("ERROR: database name missing in OPENIRN_API_MYSQL_URL.", file=sys.stderr)
        raise SystemExit(2)
    return {
        "host": parsed.hostname or "127.0.0.1",
        "port": int(parsed.port or 3306),
        "user": unquote(parsed.username or ""),
        "password": unquote(parsed.password or ""),
        "database": database,
        "charset": (query.get("charset") or ["utf8mb4"])[0] or "utf8mb4",
    }


def connect(mysql_url: str) -> Any:
    pymysql, DictCursor = import_pymysql()
    config = parse_mysql_url(mysql_url)
    try:
        return pymysql.connect(**config, autocommit=False, cursorclass=DictCursor)
    except Exception as exc:
        print(f"ERROR: MariaDB connection failed: {exc}", file=sys.stderr)
        raise SystemExit(2)


def table_exists(con: Any, table_name: str) -> bool:
    with con.cursor() as cur:
        cur.execute(
            """
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema = DATABASE() AND table_name = %s
            """,
            (table_name,),
        )
        return cur.fetchone() is not None


def table_columns(con: Any, table_name: str) -> set[str]:
    try:
        with con.cursor() as cur:
            cur.execute(
                """
                SELECT column_name
                FROM information_schema.columns
                WHERE table_schema = DATABASE() AND table_name = %s
                """,
                (table_name,),
            )
            return {str(row["column_name"]) for row in cur.fetchall()}
    except Exception:
        return set()


def fetchone(con: Any, sql: str, params: tuple[Any, ...] = ()) -> dict[str, Any] | None:
    with con.cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchone()


def fetchall(con: Any, sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    with con.cursor() as cur:
        cur.execute(sql, params)
        return list(cur.fetchall())


def execute(con: Any, sql: str, params: tuple[Any, ...] = ()) -> None:
    with con.cursor() as cur:
        cur.execute(sql, params)


def alias_target(con: Any, entity_type: str, old_id: str, scope_id: str = "") -> str:
    if not old_id or not table_exists(con, "id_aliases"):
        return ""
    try:
        row = fetchone(
            con,
            """
            SELECT new_id FROM id_aliases
            WHERE entity_type = %s AND scope_id = %s AND old_id = %s
            """,
            (entity_type, scope_id, old_id),
        )
    except Exception:
        return ""
    return str(row.get("new_id") or "") if row else ""


def resolve_tenant_id(con: Any, requested: str) -> str:
    tenant_id = tenant_argument(requested)
    row = fetchone(con, "SELECT id FROM tenants WHERE id = %s", (tenant_id,))
    if row:
        return str(row.get("id") or tenant_id)

    aliased = alias_target(con, "tenant", tenant_id)
    if aliased:
        row = fetchone(con, "SELECT id FROM tenants WHERE id = %s", (aliased,))
        if row:
            return str(row.get("id") or aliased)

    return tenant_id


def tenant_display_name(row: dict[str, Any]) -> str:
    display_name = str(row.get("display_name") or "").strip()
    if display_name:
        return display_name
    tenant_id = str(row.get("id") or "").strip()
    return "Défaut" if tenant_id == "default" else tenant_id


def tenant_counts(con: Any, tenant_id: str) -> dict[str, int]:
    counts = {
        "active_users": 0,
        "active_devices": 0,
        "pending_requests": 0,
    }
    if table_exists(con, "users"):
        row = fetchone(con, "SELECT count(*) AS total FROM users WHERE tenant_id = %s AND active = 1", (tenant_id,))
        counts["active_users"] = int(row.get("total") if row else 0)
    if table_exists(con, "authorized_devices"):
        row = fetchone(
            con,
            """
            SELECT count(*) AS total
            FROM authorized_devices
            WHERE tenant_id = %s AND status = 'active' AND revoked_at IS NULL
            """,
            (tenant_id,),
        )
        counts["active_devices"] = int(row.get("total") if row else 0)
    if table_exists(con, "device_enrollment_requests"):
        row = fetchone(
            con,
            """
            SELECT count(*) AS total
            FROM device_enrollment_requests
            WHERE tenant_id = %s AND status = 'pending'
            """,
            (tenant_id,),
        )
        counts["pending_requests"] = int(row.get("total") if row else 0)
    return counts


def print_table(headers: Iterable[str], rows: list[list[str]]) -> None:
    headers = list(headers)
    widths = [len(header) for header in headers]
    for row in rows:
        for index, value in enumerate(row):
            widths[index] = max(widths[index], len(value))

    def fmt(row: Iterable[str]) -> str:
        values = list(row)
        return "  ".join(values[index].ljust(widths[index]) for index in range(len(headers)))

    print(fmt(headers))
    print(fmt("-" * width for width in widths))
    for row in rows:
        print(fmt(row))


def list_tenants(con: Any) -> None:
    if not table_exists(con, "tenants"):
        print("Aucun espace de travail : la table tenants n’existe pas encore.")
        return

    columns = table_columns(con, "tenants")
    select_parts = ["id"]
    for column in ("display_name", "description", "permanent", "created_at", "updated_at"):
        if column in columns:
            select_parts.append(column)
    rows = fetchall(con, f"SELECT {', '.join(select_parts)} FROM tenants ORDER BY display_name ASC, id ASC")

    if not rows:
        print("Aucun espace de travail trouvé dans la base.")
        return

    table_rows: list[list[str]] = []
    for row in rows:
        tenant_id = str(row.get("id") or "")
        counts = tenant_counts(con, tenant_id)
        permanent = "oui" if int(row.get("permanent") or 0) else "non"
        table_rows.append([
            tenant_display_name(row),
            tenant_id,
            permanent,
            str(counts["active_users"]),
            str(counts["active_devices"]),
            str(counts["pending_requests"]),
        ])

    print_table(
        ["Nom affiché", "Tenant ID", "Permanent", "Utilisateurs", "Terminaux", "Demandes"],
        table_rows,
    )


def ensure_tenant(con: Any, tenant_id: str) -> None:
    """Ensure a tenant row exists without relying on partial INSERT defaults.

    MariaDB runs in strict mode in production. Even an INSERT ... ON DUPLICATE KEY
    UPDATE statement must provide values for NOT NULL columns without defaults
    before the duplicate-key branch can run. Check first, then insert a complete
    tenant row only when the tenant is genuinely missing.
    """
    now = utc_now().isoformat()
    existing = fetchone(con, "SELECT id FROM tenants WHERE id = %s", (tenant_id,))
    if existing:
        execute(
            con,
            """
            UPDATE tenants
            SET updated_at = CASE WHEN updated_at = '' THEN %s ELSE updated_at END
            WHERE id = %s
            """,
            (now, tenant_id),
        )
        return

    display_name = "Défaut" if tenant_id == "default" else tenant_id
    permanent = 1 if tenant_id == "default" else 0
    execute(
        con,
        """
        INSERT INTO tenants(id, created_at, updated_at, display_name, description, permanent)
        VALUES (%s, %s, %s, %s, %s, %s)
        """,
        (tenant_id, now, now, display_name, "", permanent),
    )


def count_active_devices(con: Any, tenant_id: str) -> int:
    row = fetchone(
        con,
        """
        SELECT count(*) AS total
        FROM authorized_devices
        WHERE tenant_id = %s AND status = 'active' AND revoked_at IS NULL
        """,
        (tenant_id,),
    )
    return int(row.get("total") if row else 0)


def record_audit(con: Any, tenant_id: str, enrollment_id: str, label: str, expires_at: str) -> None:
    try:
        execute(
            con,
            """
            INSERT INTO device_audit_log(tenant_id, device_id, event_type, created_at, payload_json)
            VALUES (%s, NULL, %s, %s, %s)
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
    except Exception:
        # The enrollment itself is more important than the audit line in a recovery path.
        pass


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create a temporary OpenIRN enrollment code directly in MariaDB.",
    )
    parser.add_argument(
        "--mysql-url",
        default=os.environ.get("OPENIRN_API_MYSQL_URL", ""),
        help="MariaDB URL. Default: OPENIRN_API_MYSQL_URL",
    )
    parser.add_argument(
        "--list-tenants",
        "--list-tenant",
        dest="list_tenants",
        action="store_true",
        help="List existing tenants with their id, then exit without creating an enrollment code.",
    )
    parser.add_argument("--tenant", default="default", help="Tenant id or legacy alias. Default: %(default)s")
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

    requested_tenant_id = tenant_argument(args.tenant)
    con = connect(args.mysql_url)
    try:
        if args.list_tenants:
            print("OpenIRN tenants")
            print("---------------")
            print("Database: MariaDB")
            print()
            list_tenants(con)
            return 0

        tenant_id = resolve_tenant_id(con, requested_tenant_id)
        ensure_tenant(con, tenant_id)

        raw_code = new_code()
        display_code = format_code(raw_code)
        normalized_code = normalize_code(raw_code)
        enrollment_id = f"enrollment_{uuid.uuid4().hex}"
        now = utc_now()
        expires_at = (now + timedelta(minutes=args.expires)).isoformat()
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
        enrollment_secret = enrollment_code_secret()

        execute(
            con,
            """
            INSERT INTO device_enrollment_codes(
                tenant_id, enrollment_id, code_hash, created_by_user_id, label,
                expires_at, consumed_at, consumed_by_device_id, created_at
            ) VALUES (%s, %s, %s, %s, %s, %s, NULL, NULL, %s)
            """,
            (
                tenant_id,
                enrollment_id,
                code_hash(tenant_id, normalized_code, enrollment_secret),
                "server-bootstrap",
                str(args.label or "Bootstrap terminal")[:120],
                expires_at,
                now.isoformat(),
            ),
        )
        record_audit(con, tenant_id, enrollment_id, str(args.label or "Bootstrap terminal")[:120], expires_at)
        con.commit()
    finally:
        con.close()

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
    print("Database     : MariaDB")
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
