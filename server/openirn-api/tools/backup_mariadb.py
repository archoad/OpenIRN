#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, unquote, urlparse

APP_DIR = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP_DIR))

from database_contract import REQUIRED_MIGRATIONS, REQUIRED_TABLES  # noqa: E402
from observability import (  # noqa: E402
    build_operation_event,
    emit_operation_event,
)
from version import APP_VERSION  # noqa: E402


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def pretty_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True)


def parse_mysql_url(raw: str) -> dict[str, Any]:
    if not raw:
        raise SystemExit("[ERREUR] OPENIRN_API_MYSQL_URL absent")
    parsed = urlparse(raw)
    if parsed.scheme not in {"mysql", "mysql+pymysql", "mariadb", "mariadb+pymysql"}:
        raise SystemExit("[ERREUR] URL MariaDB invalide")
    query = parse_qs(parsed.query)
    database = parsed.path.lstrip("/")
    if not database:
        raise SystemExit("[ERREUR] nom de base absent dans OPENIRN_API_MYSQL_URL")
    return {
        "host": parsed.hostname or "127.0.0.1",
        "port": int(parsed.port or 3306),
        "user": unquote(parsed.username or ""),
        "password": unquote(parsed.password or ""),
        "database": database,
        "charset": (query.get("charset") or ["utf8mb4"])[0] or "utf8mb4",
    }


def import_pymysql() -> Any:
    try:
        import pymysql  # type: ignore
    except ImportError:
        raise SystemExit("[ERREUR] PyMySQL absent. Installez requirements-mariadb.txt dans le venv.")
    return pymysql


def connect(config: dict[str, Any]) -> Any:
    pymysql = import_pymysql()
    return pymysql.connect(**config, autocommit=False)


def chmod_private(path: Path, mode: int) -> None:
    try:
        path.chmod(mode)
    except PermissionError:
        current = stat.S_IMODE(path.stat().st_mode)
        if current != mode:
            raise


def ensure_private_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    chmod_private(path, 0o700)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def backup_signature(metadata: dict[str, Any], secret: str | None = None) -> str:
    effective_secret = (
        str(secret).strip()
        if secret is not None
        else os.environ.get("OPENIRN_API_BACKUP_SIGNATURE_SECRET", "").strip()
    )
    if len(effective_secret) < 32:
        raise RuntimeError("OPENIRN_API_BACKUP_SIGNATURE_SECRET doit contenir au moins 32 caractères")
    payload = dict(metadata)
    payload.pop("signature", None)
    payload.pop("signatureStatus", None)
    payload.pop("signatureAlgorithm", None)
    return hmac.new(
        effective_secret.encode("utf-8"),
        canonical_json(payload).encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def dump_binary() -> str:
    configured = os.environ.get("OPENIRN_MARIADB_DUMP_BIN", "").strip()
    if configured:
        return configured
    return shutil.which("mariadb-dump") or shutil.which("mysqldump") or ""


def read_counts(config: dict[str, Any]) -> dict[str, int]:
    con = connect(config)
    try:
        with con.cursor() as cur:
            cur.execute(
                """
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE'
                ORDER BY table_name
                """
            )
            tables = [str(row[0]) for row in cur.fetchall()]
            missing = sorted(set(REQUIRED_TABLES) - set(tables))
            if missing:
                raise RuntimeError(f"Schéma OpenIRN incomplet: {', '.join(missing)}")

            counts: dict[str, int] = {}
            for table in tables:
                escaped_table = table.replace("`", "``")
                cur.execute(f"SELECT COUNT(*) FROM `{escaped_table}`")
                counts[table] = int(cur.fetchone()[0])
            return counts
    finally:
        con.close()


def verify_backup_artifacts(backup_path: Path, secret: str | None = None) -> dict[str, Any]:
    if not backup_path.is_file():
        raise RuntimeError(f"Dump MariaDB introuvable: {backup_path}")
    sha_path = backup_path.with_suffix(backup_path.suffix + ".sha256")
    meta_path = backup_path.with_suffix(backup_path.suffix + ".json")
    if not sha_path.is_file() or not meta_path.is_file():
        raise RuntimeError("Le dump, son SHA-256 et son manifeste signé sont indissociables")

    digest = file_sha256(backup_path)
    sha_parts = sha_path.read_text(encoding="utf-8").split()
    expected_sha = sha_parts[0].strip() if sha_parts else ""
    if len(expected_sha) != 64 or not hmac.compare_digest(digest, expected_sha):
        raise RuntimeError("SHA-256 du dump MariaDB invalide")

    try:
        metadata = json.loads(meta_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError("Manifeste de sauvegarde illisible") from exc
    if not isinstance(metadata, dict):
        raise RuntimeError("Manifeste de sauvegarde invalide")
    if int(metadata.get("formatVersion") or 0) < 2:
        raise RuntimeError("Format de sauvegarde antérieur à la procédure DBA vérifiée")
    if str(metadata.get("databaseScope") or "") != "all_tenants":
        raise RuntimeError("Le périmètre global de la sauvegarde n’est pas déclaré")
    if str(metadata.get("backupName") or "") != backup_path.name:
        raise RuntimeError("Le manifeste ne correspond pas au nom du dump")
    if not hmac.compare_digest(str(metadata.get("sha256") or ""), digest):
        raise RuntimeError("Le SHA-256 du manifeste ne correspond pas au dump")
    if str(metadata.get("signatureAlgorithm") or "") != "hmac-sha256-canonical-json-v1":
        raise RuntimeError("Algorithme de signature de sauvegarde non accepté")
    if str(metadata.get("signatureStatus") or "") != "valid":
        raise RuntimeError("Une sauvegarde non signée ne peut pas être restaurée")

    signature = str(metadata.get("signature") or "")
    expected_signature = backup_signature(metadata, secret)
    if not signature or not hmac.compare_digest(signature, expected_signature):
        raise RuntimeError("Signature HMAC du manifeste invalide")

    counts = metadata.get("counts")
    if not isinstance(counts, dict) or set(REQUIRED_TABLES) - set(counts):
        raise RuntimeError("Les comptages du manifeste ne couvrent pas toutes les tables OpenIRN")
    migrations = metadata.get("schemaMigrations")
    expected_versions = {str(version) for version in REQUIRED_MIGRATIONS}
    if not isinstance(migrations, dict) or expected_versions - set(migrations):
        raise RuntimeError("Le manifeste ne couvre pas toutes les migrations OpenIRN requises")
    return metadata


def read_schema_migrations(config: dict[str, Any]) -> dict[str, str]:
    con = connect(config)
    try:
        with con.cursor() as cur:
            cur.execute("SELECT version, name FROM schema_migrations ORDER BY version")
            return {str(int(version)): str(name or "") for version, name in cur.fetchall()}
    finally:
        con.close()


def record_audit(config: dict[str, Any], backup_name: str, sha256: str, size_bytes: int, reason: str, automatic: bool) -> None:
    try:
        con = connect(config)
        try:
            with con.cursor() as cur:
                now = utc_now().isoformat()
                cur.execute(
                    """
                    INSERT INTO backup_audit_log(
                        tenant_id, backup_name, event_type, reason,
                        triggered_by_user_id, created_at, sha256, size_bytes, payload_json
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        "default",
                        backup_name[:240],
                        "backup.created",
                        reason[:160],
                        "systemd-timer" if automatic else "server-cli",
                        now,
                        sha256,
                        int(size_bytes),
                        canonical_json({"backend": "mariadb", "automatic": automatic}),
                    ),
                )
            con.commit()
        finally:
            con.close()
    except Exception:
        pass


def cleanup_old_backups(backup_dir: Path, keep: int) -> list[str]:
    if keep <= 0:
        return []
    backups = sorted(backup_dir.glob("openirn-*.mariadb.sql"), key=lambda item: item.stat().st_mtime, reverse=True)
    removed: list[str] = []
    for old in backups[keep:]:
        for companion in [old, old.with_suffix(old.suffix + ".sha256"), old.with_suffix(old.suffix + ".json")]:
            if companion.exists():
                companion.unlink()
        removed.append(old.name)
    return removed


def create_backup(backup_dir: Path, keep: int, reason: str, automatic: bool, verbose: bool) -> dict[str, Any]:
    config = parse_mysql_url(os.environ.get("OPENIRN_API_MYSQL_URL", "").strip())
    if len(os.environ.get("OPENIRN_API_BACKUP_SIGNATURE_SECRET", "").strip()) < 32:
        raise SystemExit("[ERREUR] OPENIRN_API_BACKUP_SIGNATURE_SECRET doit contenir au moins 32 caractères")
    binary = dump_binary()
    if not binary:
        raise SystemExit("[ERREUR] mariadb-dump/mysqldump introuvable")
    ensure_private_dir(backup_dir)

    stamp = utc_now().strftime("%Y%m%dT%H%M%SZ")
    backup_path = backup_dir / f"openirn-{stamp}.mariadb.sql"
    suffix = 1
    while backup_path.exists():
        backup_path = backup_dir / f"openirn-{stamp}-{suffix}.mariadb.sql"
        suffix += 1

    defaults_path = backup_dir / f".openirn-mariadb-client-{uuid.uuid4().hex}.cnf"
    defaults_path.write_text(
        "\n".join(
            [
                "[client]",
                f"host={config['host']}",
                f"port={config['port']}",
                f"user={config['user']}",
                f"password={config['password']}",
                f"default-character-set={config.get('charset') or 'utf8mb4'}",
                "",
            ]
        ),
        encoding="utf-8",
    )
    chmod_private(defaults_path, 0o600)
    cmd = [
        binary,
        f"--defaults-extra-file={defaults_path}",
        "--single-transaction",
        "--quick",
        "--skip-comments",
        "--hex-blob",
        "--no-tablespaces",
        config["database"],
    ]
    try:
        with backup_path.open("wb") as output:
            proc = subprocess.run(cmd, stdout=output, stderr=subprocess.PIPE, check=False)
        if proc.returncode != 0:
            stderr = proc.stderr.decode("utf-8", errors="replace") if isinstance(proc.stderr, bytes) else str(proc.stderr or "")
            if backup_path.exists():
                backup_path.unlink()
            raise SystemExit(f"[ERREUR] dump MariaDB impossible: {stderr[-600:]}")
    finally:
        try:
            defaults_path.unlink()
        except OSError:
            pass

    chmod_private(backup_path, 0o600)
    digest = file_sha256(backup_path)
    sha_path = backup_path.with_suffix(backup_path.suffix + ".sha256")
    sha_path.write_text(f"{digest}  {backup_path.name}\n", encoding="utf-8")
    chmod_private(sha_path, 0o600)

    metadata: dict[str, Any] = {
        "type": "openirn.mariadbDumpBackup",
        "formatVersion": 2,
        "backend": "mariadb",
        "databaseScope": "all_tenants",
        "createdAt": utc_now().isoformat(),
        "sourceDb": f"{config['user']}@{config['host']}:{config['port']}/{config['database']}",
        "sourceDatabase": config["database"],
        "backupDb": str(backup_path),
        "backupName": backup_path.name,
        "reason": reason,
        "automatic": automatic,
        "triggeredByUserId": "systemd-timer" if automatic else "server-cli",
        "sha256": digest,
        "sizeBytes": backup_path.stat().st_size,
        "integrityCheck": "logical_dump_created",
        "retentionKeep": keep,
        "counts": read_counts(config),
        "schemaMigrations": read_schema_migrations(config),
    }
    signature = backup_signature(metadata)
    metadata["signatureAlgorithm"] = "hmac-sha256-canonical-json-v1"
    metadata["signature"] = signature
    metadata["signatureStatus"] = "valid"

    meta_path = backup_path.with_suffix(backup_path.suffix + ".json")
    meta_path.write_text(pretty_json(metadata) + "\n", encoding="utf-8")
    chmod_private(meta_path, 0o600)
    removed = cleanup_old_backups(backup_dir, keep)
    record_audit(config, backup_path.name, digest, backup_path.stat().st_size, reason, automatic)
    metadata["removedOldBackups"] = removed
    if verbose:
        print(f"Backup MariaDB créé : {backup_path}")
        print(f"SHA-256             : {digest}")
        print(f"Signature           : {metadata['signatureStatus']}")
        if removed:
            print("Anciennes sauvegardes supprimées:", ", ".join(removed))
    return metadata


def main() -> int:
    parser = argparse.ArgumentParser(description="Create an OpenIRN MariaDB logical backup.")
    parser.add_argument(
        "--backup-dir",
        default=os.environ.get("OPENIRN_API_BACKUP_DIR", "/var/lib/openirn-api/backups"),
        help="Backup directory. Default: %(default)s",
    )
    parser.add_argument(
        "--keep",
        type=int,
        default=int(os.environ.get("OPENIRN_API_BACKUP_KEEP", "30")),
        help="Number of backups to keep. Default: %(default)s",
    )
    parser.add_argument("--reason", default="scheduled", help="Audit reason.")
    parser.add_argument("--manual", action="store_true", help="Mark the backup as manual instead of scheduled.")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    try:
        metadata = create_backup(
            Path(args.backup_dir),
            max(1, args.keep),
            args.reason,
            automatic=not args.manual,
            verbose=args.verbose,
        )
    except BaseException as exc:
        emit_operation_event(
            build_operation_event(
                "backup.failed",
                service_version=APP_VERSION,
                successful=False,
                automatic=not args.manual,
                reason=type(exc).__name__,
            )
        )
        raise
    emit_operation_event(
        build_operation_event(
            "backup.created",
            service_version=APP_VERSION,
            automatic=not args.manual,
            reason=args.reason,
            size_bytes=int(metadata.get("sizeBytes") or 0),
            signature_status=str(metadata.get("signatureStatus") or ""),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
