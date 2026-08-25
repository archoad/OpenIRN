#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

APP_DIR = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP_DIR))

from database_contract import REQUIRED_TABLES  # noqa: E402

TABLES = list(REQUIRED_TABLES)


def parse_mysql_url() -> dict[str, object]:
    raw = os.environ.get("OPENIRN_API_MYSQL_URL", "").strip()
    if not raw:
        raise SystemExit("[ERREUR] OPENIRN_API_MYSQL_URL absent")
    parsed = urlparse(raw)
    if parsed.scheme not in {"mysql", "mysql+pymysql", "mariadb", "mariadb+pymysql"}:
        raise SystemExit("[ERREUR] OPENIRN_API_MYSQL_URL doit utiliser mysql+pymysql:// ou mariadb+pymysql://")
    query = parse_qs(parsed.query)
    database = parsed.path.lstrip("/")
    if not database:
        raise SystemExit("[ERREUR] base absente dans OPENIRN_API_MYSQL_URL")
    return {
        "host": parsed.hostname or "127.0.0.1",
        "port": int(parsed.port or 3306),
        "user": unquote(parsed.username or ""),
        "password": unquote(parsed.password or ""),
        "database": database,
        "charset": (query.get("charset") or ["utf8mb4"])[0] or "utf8mb4",
    }


def main() -> int:
    try:
        import pymysql  # type: ignore
    except ImportError:
        print("[ERREUR] PyMySQL absent. Installez requirements-mariadb.txt dans le venv.")
        return 1

    config = parse_mysql_url()
    print("Backend runtime : mariadb")
    print(f"Cible MariaDB   : {config['user']}@{config['host']}:{config['port']}/{config['database']}")
    try:
        con = pymysql.connect(**config, autocommit=True)
    except Exception as exc:
        print(f"[ERREUR] Connexion MariaDB impossible: {exc}")
        return 1
    try:
        with con.cursor() as cur:
            cur.execute("SELECT VERSION()")
            print("Version MariaDB :", cur.fetchone()[0])
            for table in TABLES:
                try:
                    cur.execute(f"SELECT COUNT(*) FROM `{table}`")
                    count = cur.fetchone()[0]
                except Exception:
                    count = -1
                print(f"  {table:<36} {count}")
    finally:
        con.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
