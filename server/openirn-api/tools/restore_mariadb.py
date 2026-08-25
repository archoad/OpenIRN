#!/usr/bin/env python3
"""Verify and restore an OpenIRN backup into an empty DBA-controlled database."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import backup_mariadb as backup


ORPHAN_CHECKS = {
    "users_without_tenant": """
        SELECT COUNT(*) FROM users child
        LEFT JOIN tenants parent ON parent.id = child.tenant_id
        WHERE parent.id IS NULL
    """,
    "credentials_without_user": """
        SELECT COUNT(*) FROM user_credentials child
        LEFT JOIN users parent
          ON parent.tenant_id = child.tenant_id AND parent.user_id = child.user_id
        WHERE parent.user_id IS NULL
    """,
    "campaigns_without_tenant": """
        SELECT COUNT(*) FROM campaign_states child
        LEFT JOIN tenants parent ON parent.id = child.tenant_id
        WHERE parent.id IS NULL
    """,
    "assets_without_system": """
        SELECT COUNT(*) FROM information_assets child
        LEFT JOIN information_systems parent
          ON parent.tenant_id = child.tenant_id AND parent.system_id = child.system_id
        WHERE parent.system_id IS NULL
    """,
    "devices_without_tenant": """
        SELECT COUNT(*) FROM authorized_devices child
        LEFT JOIN tenants parent ON parent.id = child.tenant_id
        WHERE parent.id IS NULL
    """,
}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def client_binary() -> str:
    configured = os.environ.get("OPENIRN_MARIADB_CLIENT_BIN", "").strip()
    return configured or shutil.which("mariadb") or shutil.which("mysql") or ""


def _private_defaults_file(config: dict[str, Any]) -> Path:
    descriptor, raw_path = tempfile.mkstemp(prefix="openirn-restore-", suffix=".cnf")
    path = Path(raw_path)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        handle.write(
            "[client]\n"
            f"host={config['host']}\n"
            f"port={config['port']}\n"
            f"user={config['user']}\n"
            f"password={config['password']}\n"
            f"default-character-set={config.get('charset') or 'utf8mb4'}\n"
        )
    path.chmod(0o600)
    return path


def _target_is_empty(config: dict[str, Any]) -> bool:
    con = backup.connect(config)
    try:
        with con.cursor() as cur:
            cur.execute(
                """
                SELECT COUNT(*)
                FROM information_schema.tables
                WHERE table_schema = %s AND table_type = 'BASE TABLE'
                """,
                (config["database"],),
            )
            return int(cur.fetchone()[0]) == 0
    finally:
        con.close()


def _restore_dump(backup_path: Path, config: dict[str, Any]) -> None:
    binary = client_binary()
    if not binary:
        raise RuntimeError("Client mariadb/mysql introuvable")
    if not _target_is_empty(config):
        raise RuntimeError("La base cible n’est pas vide; aucune donnée existante ne sera écrasée")

    defaults_path = _private_defaults_file(config)
    command = [
        binary,
        f"--defaults-extra-file={defaults_path}",
        f"--database={config['database']}",
    ]
    try:
        with backup_path.open("rb") as source:
            process = subprocess.run(
                command,
                stdin=source,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                check=False,
            )
        if process.returncode != 0:
            stderr = process.stderr.decode("utf-8", errors="replace")
            raise RuntimeError(f"Restauration MariaDB interrompue: {stderr[-800:]}")
    finally:
        try:
            defaults_path.unlink()
        except OSError:
            pass


def _post_restore_checks(config: dict[str, Any], metadata: dict[str, Any]) -> dict[str, Any]:
    restored_counts = backup.read_counts(config)
    expected_counts = metadata["counts"]
    count_mismatches = {
        table: {
            "expected": None if expected is None else int(expected),
            "restored": int(restored_counts.get(table, -1)),
        }
        for table, expected in expected_counts.items()
        if expected is None or int(restored_counts.get(table, -1)) != int(expected)
    }

    restored_migrations = backup.read_schema_migrations(config)
    expected_migrations = {
        str(version): str(name or "")
        for version, name in metadata["schemaMigrations"].items()
    }
    migration_mismatches = {
        version: {"expected": name, "restored": restored_migrations.get(version)}
        for version, name in expected_migrations.items()
        if restored_migrations.get(version) != name
    }

    con = backup.connect(config)
    try:
        with con.cursor() as cur:
            cur.execute("SELECT @@FOREIGN_KEY_CHECKS")
            foreign_key_checks = int(cur.fetchone()[0])
            orphan_counts: dict[str, int] = {}
            for name, sql in ORPHAN_CHECKS.items():
                cur.execute(sql)
                orphan_counts[name] = int(cur.fetchone()[0])
    finally:
        con.close()

    failures = {
        "countMismatches": count_mismatches,
        "migrationMismatches": migration_mismatches,
        "orphanCounts": {name: count for name, count in orphan_counts.items() if count},
    }
    if foreign_key_checks != 1 or any(failures.values()):
        raise RuntimeError(f"Contrôles post-restauration en échec: {json.dumps(failures, sort_keys=True)}")

    return {
        "tableCounts": restored_counts,
        "schemaMigrations": restored_migrations,
        "foreignKeyChecks": foreign_key_checks,
        "orphanCounts": orphan_counts,
    }


def restore(
    backup_path: Path,
    *,
    restore_requested: bool,
    target_mysql_url: str,
    confirmed_database: str,
    allow_non_drill_target: bool,
) -> dict[str, Any]:
    metadata = backup.verify_backup_artifacts(backup_path)
    report: dict[str, Any] = {
        "type": "openirn.mariadbRestoreVerification",
        "verifiedAt": utc_now(),
        "backupName": backup_path.name,
        "sha256": metadata["sha256"],
        "signatureStatus": "valid",
        "databaseScope": metadata["databaseScope"],
        "restorePerformed": False,
    }
    if not restore_requested:
        return report

    if not target_mysql_url:
        raise RuntimeError("OPENIRN_RESTORE_MYSQL_URL est requis pour restaurer")
    config = backup.parse_mysql_url(target_mysql_url)
    database = str(config["database"])
    if confirmed_database != database:
        raise RuntimeError("--confirm-target doit reprendre exactement le nom de la base cible")
    if not allow_non_drill_target and not database.startswith("openirn_restore_"):
        raise RuntimeError(
            "Une restauration de test doit cibler une base openirn_restore_*; "
            "utilisez --allow-non-drill-target uniquement pour une bascule DBA préparée"
        )
    source_database = str(metadata.get("sourceDatabase") or "")
    if source_database and source_database == database:
        raise RuntimeError("La restauration directe dans la base source est interdite")

    _restore_dump(backup_path, config)
    checks = _post_restore_checks(config, metadata)
    report.update(
        {
            "restoredAt": utc_now(),
            "restorePerformed": True,
            "targetDatabase": database,
            "checks": checks,
        }
    )
    return report


def _write_report(path: Path, report: dict[str, Any]) -> None:
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    try:
        path.chmod(0o600)
    except OSError:
        if stat.S_IMODE(path.stat().st_mode) != 0o600:
            raise


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify an OpenIRN MariaDB backup and optionally restore it into an empty database."
    )
    parser.add_argument("--backup", type=Path, required=True)
    parser.add_argument("--restore", action="store_true")
    parser.add_argument("--confirm-target", default="")
    parser.add_argument("--allow-non-drill-target", action="store_true")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    try:
        report = restore(
            args.backup.resolve(),
            restore_requested=args.restore,
            target_mysql_url=os.environ.get("OPENIRN_RESTORE_MYSQL_URL", "").strip(),
            confirmed_database=args.confirm_target,
            allow_non_drill_target=args.allow_non_drill_target,
        )
        if args.report:
            _write_report(args.report, report)
    except Exception as exc:
        print(f"[ERREUR] Vérification/restauration refusée: {exc}", file=sys.stderr)
        return 1

    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
