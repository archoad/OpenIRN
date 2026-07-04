#!/usr/bin/env python3
"""Check MariaDB readiness for the OpenIRN server runtime."""

from __future__ import annotations

import argparse
import os
import sys
from typing import Any
from urllib.parse import parse_qs, unquote, urlparse

EXPECTED_TABLES = [
    "schema_migrations",
    "tenants",
    "users",
    "user_credentials",
    "sync_snapshots",
    "campaign_states",
    "campaign_revisions",
    "critical_functions",
    "information_systems",
    "information_assets",
    "terminals",
    "authorized_devices",
    "device_enrollment_requests",
    "device_enrollment_codes",
    "api_sessions",
    "auth_attempts",
    "device_audit_log",
    "official_referentials",
    "official_referential_history",
    "sync_events",
    "backup_audit_log",
    "id_aliases",
]


def fail(message: str) -> None:
    print(f"[ERREUR] {message}", file=sys.stderr)
    raise SystemExit(1)


def import_pymysql() -> Any:
    try:
        import pymysql  # type: ignore
        from pymysql.cursors import DictCursor  # type: ignore
    except ImportError:
        fail(
            "PyMySQL est absent. Installe-le dans le venv serveur : "
            "pip install -r server/openirn-api/requirements-mariadb.txt"
        )
    return pymysql, DictCursor


def parse_mysql_url(url: str) -> dict[str, Any]:
    parsed = urlparse(url)
    if parsed.scheme not in {"mysql", "mysql+pymysql", "mariadb", "mariadb+pymysql"}:
        fail("URL MariaDB invalide")
    query = parse_qs(parsed.query)
    database = parsed.path.lstrip("/")
    if not database:
        fail("Nom de base absent dans l'URL MariaDB")
    return {
        "host": parsed.hostname or "127.0.0.1",
        "port": int(parsed.port or 3306),
        "user": unquote(parsed.username or ""),
        "password": unquote(parsed.password or ""),
        "database": database,
        "charset": query.get("charset", ["utf8mb4"])[0],
    }


def config_from_args(args: argparse.Namespace) -> dict[str, Any]:
    url = args.mysql_url or os.environ.get("OPENIRN_API_MYSQL_URL", "").strip()
    if url:
        config = parse_mysql_url(url)
    else:
        config = {
            "host": args.host or os.environ.get("OPENIRN_MARIADB_HOST", "127.0.0.1"),
            "port": int(args.port or os.environ.get("OPENIRN_MARIADB_PORT", "3306")),
            "user": args.user or os.environ.get("OPENIRN_MARIADB_USER", "openirn_api"),
            "password": args.password if args.password is not None else os.environ.get("OPENIRN_MARIADB_PASSWORD", ""),
            "database": args.database or os.environ.get("OPENIRN_MARIADB_DATABASE", "openirn"),
            "charset": args.charset or os.environ.get("OPENIRN_MARIADB_CHARSET", "utf8mb4"),
        }
    if not config["user"] or not config["database"]:
        fail("Configuration MariaDB incomplète")
    return config


def connect(config: dict[str, Any]) -> Any:
    pymysql, DictCursor = import_pymysql()
    try:
        return pymysql.connect(
            host=config["host"],
            port=int(config["port"]),
            user=config["user"],
            password=config["password"],
            database=config["database"],
            charset=config.get("charset") or "utf8mb4",
            autocommit=True,
            cursorclass=DictCursor,
        )
    except Exception as exc:
        fail(f"Connexion MariaDB impossible: {exc}")


def table_counts(mysql: Any) -> dict[str, int]:
    counts: dict[str, int] = {}
    with mysql.cursor() as cur:
        for table in EXPECTED_TABLES:
            try:
                cur.execute(f"SELECT COUNT(*) AS total FROM `{table}`")
                row = cur.fetchone() or {"total": 0}
                counts[table] = int(row["total"] or 0)
            except Exception:
                counts[table] = -1
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description="Check OpenIRN MariaDB readiness.")
    parser.add_argument("--mysql-url", default="", help="mysql+pymysql://user:password@host:3306/openirn?charset=utf8mb4")
    parser.add_argument("--host", default="")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--database", default="")
    parser.add_argument("--user", default="")
    parser.add_argument("--password", default=None)
    parser.add_argument("--charset", default="")
    args = parser.parse_args()

    config = config_from_args(args)
    mysql = connect(config)
    try:
        with mysql.cursor() as cur:
            cur.execute("SELECT VERSION() AS version")
            version = str((cur.fetchone() or {}).get("version") or "unknown")
            cur.execute("SELECT @@character_set_database AS charset, @@collation_database AS collation")
            charset_row = cur.fetchone() or {}
        print(f"MariaDB OK: {version}")
        print(f"Database charset: {charset_row.get('charset')} / {charset_row.get('collation')}")
        counts = table_counts(mysql)
        missing = [table for table, count in counts.items() if count < 0]
        if missing:
            print("Tables manquantes ou illisibles:", ", ".join(missing), file=sys.stderr)
            return 2
        print("Tables OpenIRN:")
        for table in EXPECTED_TABLES:
            print(f"  {table:<36} {counts[table]}")
        return 0
    finally:
        try:
            mysql.close()
        except Exception:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
