#!/usr/bin/env python3
"""Reset OpenIRN device access and user PINs for a controlled PoC baseline.

The command is read-only unless ``--apply`` is combined with the explicit
backup and confirmation flags. It never removes canonical terminal identities
or audit history.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from typing import Any, Callable
from urllib.parse import parse_qs, unquote, urlparse

INITIAL_POC_PIN = "0000"
CONFIRMATION_TEXT = "RESET-ALL-POC-ACCESS"
REQUIRED_TABLES = {
    "api_sessions",
    "authorized_devices",
    "device_audit_log",
    "device_enrollment_codes",
    "device_enrollment_requests",
    "schema_migrations",
    "tenants",
    "user_credentials",
    "users",
}
REQUIRED_MIGRATIONS = {169, 170}


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def pin_hash(pin: str, salt: str, iterations: int) -> str:
    return hashlib.pbkdf2_hmac(
        "sha256",
        str(pin or "").encode("utf-8"),
        salt.encode("utf-8"),
        iterations,
    ).hex()


def parse_mysql_url(raw: str) -> dict[str, Any]:
    if not raw:
        raise ValueError("OPENIRN_API_MYSQL_URL est requis")
    parsed = urlparse(raw)
    if parsed.scheme not in {"mysql", "mysql+pymysql", "mariadb", "mariadb+pymysql"}:
        raise ValueError("OPENIRN_API_MYSQL_URL doit utiliser mysql+pymysql:// ou mariadb+pymysql://")
    database = parsed.path.lstrip("/")
    if not database:
        raise ValueError("OPENIRN_API_MYSQL_URL ne contient pas de nom de base")
    query = parse_qs(parsed.query)
    return {
        "host": parsed.hostname or "127.0.0.1",
        "port": int(parsed.port or 3306),
        "user": unquote(parsed.username or ""),
        "password": unquote(parsed.password or ""),
        "database": database,
        "charset": (query.get("charset") or ["utf8mb4"])[0] or "utf8mb4",
    }


def connect(mysql_url: str) -> Any:
    try:
        import pymysql  # type: ignore
        from pymysql.cursors import DictCursor  # type: ignore
    except ImportError:
        raise RuntimeError(
            "PyMySQL est absent; installe requirements-mariadb.txt dans le venv serveur"
        ) from None

    return pymysql.connect(
        **parse_mysql_url(mysql_url),
        autocommit=False,
        cursorclass=DictCursor,
    )


def fetchall(con: Any, sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    with con.cursor() as cur:
        cur.execute(sql, params)
        return list(cur.fetchall())


def fetchone(con: Any, sql: str, params: tuple[Any, ...] = ()) -> dict[str, Any] | None:
    with con.cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchone()


def execute(con: Any, sql: str, params: tuple[Any, ...] = ()) -> int:
    with con.cursor() as cur:
        cur.execute(sql, params)
        return int(cur.rowcount)


def validate_apply_request(*, apply: bool, backup_confirmed: bool, confirmation: str) -> None:
    if not apply:
        return
    if not backup_confirmed:
        raise ValueError("--backup-confirmed est obligatoire avec --apply")
    if confirmation != CONFIRMATION_TEXT:
        raise ValueError(f"--confirm doit valoir exactement {CONFIRMATION_TEXT}")


def resolve_tenant_ids(con: Any, *, all_tenants: bool, requested: list[str]) -> list[str]:
    if all_tenants:
        rows = fetchall(con, "SELECT id FROM tenants ORDER BY id")
        tenant_ids = [str(row.get("id") or "").strip() for row in rows]
        return [tenant_id for tenant_id in tenant_ids if tenant_id]

    tenant_ids = list(dict.fromkeys(value.strip() for value in requested if value.strip()))
    if not tenant_ids:
        raise ValueError("utilise --all-tenants ou au moins un --tenant")
    placeholders = ",".join("%s" for _ in tenant_ids)
    rows = fetchall(
        con,
        f"SELECT id FROM tenants WHERE id IN ({placeholders}) ORDER BY id",
        tuple(tenant_ids),
    )
    existing = {str(row.get("id") or "").strip() for row in rows}
    missing = sorted(set(tenant_ids) - existing)
    if missing:
        raise ValueError(f"espace(s) introuvable(s): {', '.join(missing)}")
    return tenant_ids


def verify_schema(con: Any) -> None:
    rows = fetchall(
        con,
        """
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE'
        """,
    )
    tables = {str(row.get("table_name") or "") for row in rows}
    missing = sorted(REQUIRED_TABLES - tables)
    if missing:
        raise RuntimeError(f"schéma MariaDB incomplet: {', '.join(missing)}")
    migration_rows = fetchall(
        con,
        "SELECT version FROM schema_migrations WHERE version IN (169, 170)",
    )
    migrations = {int(row.get("version") or 0) for row in migration_rows}
    missing_migrations = sorted(REQUIRED_MIGRATIONS - migrations)
    if missing_migrations:
        raise RuntimeError(
            "migrations de sécurité absentes: "
            + ", ".join(str(version) for version in missing_migrations)
        )


def _scope_clause(tenant_ids: list[str]) -> tuple[str, tuple[str, ...]]:
    if not tenant_ids:
        raise ValueError("aucun espace de travail dans le périmètre")
    return ",".join("%s" for _ in tenant_ids), tuple(tenant_ids)


def _count(con: Any, table: str, tenant_ids: list[str], extra: str = "") -> int:
    placeholders, params = _scope_clause(tenant_ids)
    row = fetchone(
        con,
        f"SELECT COUNT(*) AS total FROM {table} WHERE tenant_id IN ({placeholders}) {extra}",
        params,
    )
    return int(row.get("total") if row else 0)


def collect_counts(con: Any, tenant_ids: list[str]) -> dict[str, int]:
    return {
        "tenants": len(tenant_ids),
        "users": _count(con, "users", tenant_ids),
        "credentials": _count(con, "user_credentials", tenant_ids),
        "authorizedDevices": _count(con, "authorized_devices", tenant_ids),
        "activeSessions": _count(con, "api_sessions", tenant_ids, "AND revoked_at IS NULL"),
        "openEnrollmentRequests": _count(
            con,
            "device_enrollment_requests",
            tenant_ids,
            "AND status IN ('pending', 'approved')",
        ),
        "unusedEnrollmentCodes": _count(
            con,
            "device_enrollment_codes",
            tenant_ids,
            "AND consumed_at IS NULL",
        ),
    }


def reset_access(
    con: Any,
    tenant_ids: list[str],
    *,
    iterations: int,
    salt_factory: Callable[[], str] | None = None,
) -> dict[str, int]:
    if iterations < 100_000:
        raise ValueError("OPENIRN_PIN_ITERATIONS doit être supérieur ou égal à 100000")
    salt_factory = salt_factory or (lambda: os.urandom(16).hex())
    before_by_tenant = {
        tenant_id: collect_counts(con, [tenant_id]) for tenant_id in tenant_ids
    }
    placeholders, scope_params = _scope_clause(tenant_ids)
    now = utc_now().isoformat()

    users = fetchall(
        con,
        f"SELECT tenant_id, user_id FROM users WHERE tenant_id IN ({placeholders}) ORDER BY tenant_id, user_id",
        scope_params,
    )

    changed = {
        "credentialsReset": 0,
        "sessionsRevoked": execute(
            con,
            f"UPDATE api_sessions SET revoked_at = %s WHERE tenant_id IN ({placeholders}) AND revoked_at IS NULL",
            (now, *scope_params),
        ),
        "enrollmentRequestsExpired": execute(
            con,
            f"""
            UPDATE device_enrollment_requests
            SET status = 'expired', decided_at = COALESCE(decided_at, %s),
                decision_note = CASE
                    WHEN decision_note = '' THEN 'Réinitialisation accès PoC'
                    ELSE decision_note
                END
            WHERE tenant_id IN ({placeholders}) AND status IN ('pending', 'approved')
            """,
            (now, *scope_params),
        ),
        "enrollmentCodesExpired": execute(
            con,
            f"""
            UPDATE device_enrollment_codes
            SET expires_at = %s
            WHERE tenant_id IN ({placeholders}) AND consumed_at IS NULL
            """,
            (now, *scope_params),
        ),
        "deviceAuthorizationsDeleted": 0,
    }

    for user in users:
        tenant_id = str(user.get("tenant_id") or "").strip()
        user_id = str(user.get("user_id") or "").strip()
        salt = salt_factory()
        execute(
            con,
            """
            INSERT INTO user_credentials(
                tenant_id, user_id, algorithm, iterations, salt, pin_hash,
                requires_change, updated_at
            ) VALUES (%s, %s, 'pbkdf2_sha256', %s, %s, %s, 1, %s)
            ON DUPLICATE KEY UPDATE
                algorithm = VALUES(algorithm),
                iterations = VALUES(iterations),
                salt = VALUES(salt),
                pin_hash = VALUES(pin_hash),
                requires_change = VALUES(requires_change),
                updated_at = VALUES(updated_at)
            """,
            (
                tenant_id,
                user_id,
                iterations,
                salt,
                pin_hash(INITIAL_POC_PIN, salt, iterations),
                now,
            ),
        )
        changed["credentialsReset"] += 1

    changed["deviceAuthorizationsDeleted"] = execute(
        con,
        f"DELETE FROM authorized_devices WHERE tenant_id IN ({placeholders})",
        scope_params,
    )

    for tenant_id in tenant_ids:
        execute(
            con,
            """
            INSERT INTO device_audit_log(
                tenant_id, device_id, event_type, created_at, payload_json
            ) VALUES (%s, NULL, %s, %s, %s)
            """,
            (
                tenant_id,
                "maintenance.poc_access_reset",
                now,
                canonical_json(
                    {
                        "initialPinTemporary": True,
                        "requiresChange": True,
                        "scope": "tenant",
                        "before": before_by_tenant[tenant_id],
                    }
                ),
            ),
        )

    con.commit()
    return changed


def print_counts(title: str, counts: dict[str, int]) -> None:
    print(title)
    print("-" * len(title))
    for key, value in counts.items():
        print(f"{key}: {value}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Réinitialise les accès OpenIRN pour une baseline PoC contrôlée.",
    )
    scope = parser.add_mutually_exclusive_group(required=True)
    scope.add_argument("--all-tenants", action="store_true", help="Cible tous les espaces existants.")
    scope.add_argument("--tenant", action="append", default=[], help="Cible cet identifiant exact; répétable.")
    parser.add_argument("--apply", action="store_true", help="Applique réellement la réinitialisation.")
    parser.add_argument(
        "--backup-confirmed",
        action="store_true",
        help="Confirme qu'une sauvegarde MariaDB vérifiée vient d'être effectuée.",
    )
    parser.add_argument("--confirm", default="", help=f"Avec --apply: {CONFIRMATION_TEXT}")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        validate_apply_request(
            apply=args.apply,
            backup_confirmed=args.backup_confirmed,
            confirmation=args.confirm,
        )
        iterations = int(os.environ.get("OPENIRN_PIN_ITERATIONS", "200000"))
        con = connect(os.environ.get("OPENIRN_API_MYSQL_URL", "").strip())
        try:
            verify_schema(con)
            tenant_ids = resolve_tenant_ids(
                con,
                all_tenants=bool(args.all_tenants),
                requested=list(args.tenant or []),
            )
            before = collect_counts(con, tenant_ids)
            print_counts("OpenIRN PoC access reset — preflight", before)
            print(f"Tenant IDs: {', '.join(tenant_ids)}")
            print("Initial PIN: 0000 (temporaire; changement obligatoire à la première connexion)")
            if not args.apply:
                print("Mode: DRY-RUN — aucune modification effectuée")
                return 0

            changed = reset_access(con, tenant_ids, iterations=iterations)
            print_counts("OpenIRN PoC access reset — applied", changed)
            print("Les identités de terminaux et les journaux d'audit ont été conservés.")
            return 0
        except Exception:
            con.rollback()
            raise
        finally:
            con.close()
    except (RuntimeError, ValueError) as exc:
        print(f"ERREUR: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:
        print(f"ERREUR: échec de la réinitialisation MariaDB: {type(exc).__name__}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
