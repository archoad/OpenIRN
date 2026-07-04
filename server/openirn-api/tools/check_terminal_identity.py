#!/usr/bin/env python3
"""Inspect OpenIRN global terminal identities and workspace enrollments."""
from __future__ import annotations

import argparse
import os
from typing import Any
from urllib.parse import parse_qs, unquote, urlparse

try:
    import pymysql  # type: ignore
    from pymysql.cursors import DictCursor  # type: ignore
except ImportError as exc:  # pragma: no cover - operational diagnostic
    raise SystemExit("pymysql is required. Install server/openirn-api/requirements-mariadb.txt") from exc


def _config() -> dict[str, Any]:
    raw = os.environ.get("OPENIRN_API_MYSQL_URL", "").strip()
    if not raw:
        raise SystemExit("OPENIRN_API_MYSQL_URL is not defined")
    parsed = urlparse(raw)
    query = parse_qs(parsed.query)
    database = parsed.path.lstrip("/")
    if not parsed.username or not database:
        raise SystemExit("OPENIRN_API_MYSQL_URL must include user and database")
    return {
        "host": parsed.hostname or "127.0.0.1",
        "port": parsed.port or 3306,
        "user": unquote(parsed.username or ""),
        "password": unquote(parsed.password or ""),
        "database": database,
        "charset": query.get("charset", ["utf8mb4"])[0],
        "cursorclass": DictCursor,
        "autocommit": True,
    }


def _connect() -> Any:
    return pymysql.connect(**_config())


def _print_rows(rows: list[dict[str, Any]]) -> None:
    if not rows:
        print("Aucun terminal trouvé.")
        return
    headers = ["Terminal", "Nom", "Plateforme", "Espaces", "Dernière vue"]
    data = [
        [
            str(row.get("device_id") or ""),
            str(row.get("name") or ""),
            str(row.get("platform") or ""),
            str(row.get("tenant_count") or 0),
            str(row.get("last_seen_at") or row.get("updated_at") or ""),
        ]
        for row in rows
    ]
    widths = [len(header) for header in headers]
    for line in data:
        for index, value in enumerate(line):
            widths[index] = max(widths[index], min(len(value), 48))

    def cut(value: str, width: int) -> str:
        return value if len(value) <= width else value[: max(0, width - 1)] + "…"

    print("  ".join(header.ljust(widths[index]) for index, header in enumerate(headers)))
    print("  ".join("-" * width for width in widths))
    for line in data:
        print("  ".join(cut(value, widths[index]).ljust(widths[index]) for index, value in enumerate(line)))


def main() -> int:
    parser = argparse.ArgumentParser(description="Inspect OpenIRN terminal identity consistency.")
    parser.add_argument("--device", default="", help="Limit to a single device id.")
    args = parser.parse_args()

    con = _connect()
    try:
        with con.cursor() as cur:
            cur.execute("SHOW TABLES LIKE 'terminals'")
            if cur.fetchone() is None:
                raise SystemExit("[ERREUR] table terminals absente. Redémarre l'API ou applique le schéma MariaDB.")
            sql = """
                SELECT tr.device_id, tr.name, tr.platform, tr.updated_at, tr.last_seen_at,
                       COUNT(ad.tenant_id) AS tenant_count
                FROM terminals tr
                LEFT JOIN authorized_devices ad
                  ON ad.device_id = tr.device_id
                 AND ad.status = 'active'
                 AND ad.revoked_at IS NULL
            """
            params: list[Any] = []
            if args.device:
                sql += " WHERE tr.device_id = %s"
                params.append(args.device.strip())
            sql += " GROUP BY tr.device_id, tr.name, tr.platform, tr.updated_at, tr.last_seen_at ORDER BY tr.name ASC, tr.device_id ASC"
            cur.execute(sql, params)
            rows = list(cur.fetchall())
            _print_rows(rows)

            if args.device and rows:
                cur.execute(
                    """
                    SELECT ad.tenant_id,
                           COALESCE(NULLIF(t.display_name, ''), ad.tenant_id) AS tenant_display_name,
                           ad.status, ad.created_at, ad.last_seen_at, ad.enrollment_id
                    FROM authorized_devices ad
                    LEFT JOIN tenants t ON t.id = ad.tenant_id
                    WHERE ad.device_id = %s
                    ORDER BY tenant_display_name ASC
                    """,
                    (args.device.strip(),),
                )
                print("\nEspaces associés:")
                for row in cur.fetchall():
                    print(
                        f"  - {row['tenant_display_name']} ({row['tenant_id']}) "
                        f"status={row['status']} enrollment={row.get('enrollment_id') or ''}"
                    )
        return 0
    finally:
        con.close()


if __name__ == "__main__":
    raise SystemExit(main())
