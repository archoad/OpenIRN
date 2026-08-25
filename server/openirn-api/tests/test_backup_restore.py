from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


API_DIR = Path(__file__).resolve().parents[1]
APP_DIR = API_DIR / "app"
TOOLS_DIR = API_DIR / "tools"
sys.path.insert(0, str(APP_DIR))
sys.path.insert(0, str(TOOLS_DIR))

import backup_mariadb as backup  # noqa: E402
import restore_mariadb as restore  # noqa: E402
from database_contract import REQUIRED_MIGRATIONS, REQUIRED_TABLES  # noqa: E402


class BackupIntegrityTests(unittest.TestCase):
    secret = "test-backup-signature-secret-0123456789abcdef"

    def _backup(self, directory: Path) -> Path:
        dump_path = directory / "openirn-test.mariadb.sql"
        dump_path.write_bytes(b"CREATE TABLE example (id INT);\n")
        digest = backup.file_sha256(dump_path)
        dump_path.with_suffix(dump_path.suffix + ".sha256").write_text(
            f"{digest}  {dump_path.name}\n",
            encoding="utf-8",
        )
        metadata = {
            "type": "openirn.mariadbDumpBackup",
            "formatVersion": 2,
            "backend": "mariadb",
            "databaseScope": "all_tenants",
            "backupName": dump_path.name,
            "sourceDatabase": "openirn",
            "sha256": digest,
            "counts": {table: 0 for table in REQUIRED_TABLES},
            "schemaMigrations": {
                str(version): name for version, name in REQUIRED_MIGRATIONS.items()
            },
        }
        metadata["signatureAlgorithm"] = "hmac-sha256-canonical-json-v1"
        metadata["signature"] = backup.backup_signature(metadata, self.secret)
        metadata["signatureStatus"] = "valid"
        dump_path.with_suffix(dump_path.suffix + ".json").write_text(
            json.dumps(metadata),
            encoding="utf-8",
        )
        return dump_path

    def test_signed_backup_triplet_is_verified(self):
        with tempfile.TemporaryDirectory() as raw_directory:
            dump_path = self._backup(Path(raw_directory))
            metadata = backup.verify_backup_artifacts(dump_path, self.secret)

        self.assertEqual(metadata["signatureStatus"], "valid")
        self.assertEqual(metadata["databaseScope"], "all_tenants")

    def test_tampered_dump_is_rejected(self):
        with tempfile.TemporaryDirectory() as raw_directory:
            dump_path = self._backup(Path(raw_directory))
            dump_path.write_bytes(dump_path.read_bytes() + b"-- tampered\n")
            with self.assertRaisesRegex(RuntimeError, "SHA-256"):
                backup.verify_backup_artifacts(dump_path, self.secret)

    def test_unsigned_manifest_is_rejected(self):
        with tempfile.TemporaryDirectory() as raw_directory:
            dump_path = self._backup(Path(raw_directory))
            meta_path = dump_path.with_suffix(dump_path.suffix + ".json")
            metadata = json.loads(meta_path.read_text(encoding="utf-8"))
            metadata["signature"] = ""
            metadata["signatureStatus"] = "unsigned"
            meta_path.write_text(json.dumps(metadata), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "non signée"):
                backup.verify_backup_artifacts(dump_path, self.secret)

    def test_verify_only_never_opens_a_restore_connection(self):
        with tempfile.TemporaryDirectory() as raw_directory:
            dump_path = self._backup(Path(raw_directory))
            with patch.dict(
                os.environ,
                {"OPENIRN_API_BACKUP_SIGNATURE_SECRET": self.secret},
                clear=False,
            ):
                report = restore.restore(
                    dump_path,
                    restore_requested=False,
                    target_mysql_url="",
                    confirmed_database="",
                    allow_non_drill_target=False,
                )

        self.assertFalse(report["restorePerformed"])
        self.assertEqual(report["signatureStatus"], "valid")


if __name__ == "__main__":
    unittest.main()
