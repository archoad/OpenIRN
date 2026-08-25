#!/usr/bin/env python3
"""Apply OpenIRN schema migrations with a dedicated MariaDB principal."""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Any


APP_DIR = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP_DIR))

import main as api  # noqa: E402


def _principal(mysql_url: str) -> str:
    with api._db(mysql_url) as con:
        row = con.execute("SELECT CURRENT_USER() AS principal").fetchone()
        return str(row["principal"] if row else "")


def migrate(migration_mysql_url: str, runtime_mysql_url: str) -> dict[str, Any]:
    if not migration_mysql_url:
        raise RuntimeError("OPENIRN_MIGRATION_MYSQL_URL est requis")
    if not runtime_mysql_url:
        raise RuntimeError("OPENIRN_API_MYSQL_URL est requis")

    migration_principal = _principal(migration_mysql_url)
    runtime_principal = _principal(runtime_mysql_url)
    if not migration_principal or not runtime_principal:
        raise RuntimeError("Impossible d’identifier les comptes MariaDB")
    if migration_principal.casefold() == runtime_principal.casefold():
        raise RuntimeError("Les comptes MariaDB de migration et de runtime doivent être distincts")

    api._apply_schema(migration_mysql_url)
    runtime_status = api._verify_runtime_schema()
    return {
        "migrationPrincipal": migration_principal,
        "runtimePrincipal": runtime_principal,
        "tables": runtime_status["tables"],
        "migrations": runtime_status["migrations"],
        "runtimePrivileges": runtime_status["privileges"],
    }


def main() -> int:
    try:
        result = migrate(
            os.environ.get("OPENIRN_MIGRATION_MYSQL_URL", "").strip(),
            os.environ.get("OPENIRN_API_MYSQL_URL", "").strip(),
        )
    except Exception as exc:
        print(f"[ERREUR] Migration MariaDB refusée: {exc}", file=sys.stderr)
        return 1

    print("Migrations OpenIRN appliquées et vérifiées.")
    print(f"Compte migration : {result['migrationPrincipal']}")
    print(f"Compte runtime   : {result['runtimePrincipal']}")
    print(f"Tables détectées : {result['tables']}")
    print("Versions         :", ", ".join(str(version) for version in result["migrations"]))
    print("Droits runtime   :", ", ".join(result["runtimePrivileges"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
