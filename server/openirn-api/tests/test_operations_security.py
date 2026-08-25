from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch


API_DIR = Path(__file__).resolve().parents[1]
APP_DIR = API_DIR / "app"
TOOLS_DIR = API_DIR / "tools"
sys.path.insert(0, str(APP_DIR))
sys.path.insert(0, str(TOOLS_DIR))

import main as api  # noqa: E402
import migrate_mariadb as migrate  # noqa: E402


class RuntimePrivilegeTests(unittest.TestCase):
    def test_grants_distinguish_runtime_dml_from_ddl(self):
        privileges = api._privileges_from_grants(
            [
                "GRANT USAGE ON *.* TO `openirn_runtime`@`localhost`",
                (
                    "GRANT SELECT, INSERT, UPDATE, DELETE ON `openirn`.* "
                    "TO `openirn_runtime`@`localhost`"
                ),
            ]
        )

        self.assertTrue({"SELECT", "INSERT", "UPDATE", "DELETE"}.issubset(privileges))
        self.assertFalse({"CREATE", "ALTER", "DROP", "INDEX"} & privileges)

    def test_migration_and_runtime_principals_must_differ(self):
        with patch.object(migrate, "_principal", return_value="openirn@localhost"):
            with self.assertRaisesRegex(RuntimeError, "doivent être distincts"):
                migrate.migrate("migration-url", "runtime-url")


if __name__ == "__main__":
    unittest.main()
