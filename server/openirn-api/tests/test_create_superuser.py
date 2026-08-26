from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


TOOL_PATH = Path(__file__).resolve().parents[1] / "tools" / "create_superuser.py"
SPEC = importlib.util.spec_from_file_location("create_superuser", TOOL_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class CreateSuperuserTest(unittest.TestCase):
    def test_rejects_predictable_pins(self) -> None:
        for value in ("0000", "1111", "1234", "4321", "password"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                MODULE.validate_pin(value)

    def test_accepts_non_trivial_pin(self) -> None:
        self.assertEqual(MODULE.validate_pin("84-Delta-29"), "84-Delta-29")

    def test_normalizes_tenant_identifier(self) -> None:
        self.assertEqual(MODULE.normalize_tenant("Administration OpenIRN"), "Administration_OpenIRN")

    def test_parses_mariadb_url(self) -> None:
        config = MODULE.parse_mysql_url(
            "mysql+pymysql://openirn_runtime:secret@127.0.0.1:3306/openirn?charset=utf8mb4"
        )
        self.assertEqual(config["user"], "openirn_runtime")
        self.assertEqual(config["database"], "openirn")
        self.assertEqual(config["charset"], "utf8mb4")

    def test_creates_temporary_administrator_without_storing_clear_pin(self) -> None:
        class FakeCursor:
            def __init__(self) -> None:
                self.responses = iter(({"total": 0}, None, None))
                self.statements: list[tuple[str, tuple[object, ...]]] = []

            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, traceback) -> None:
                return None

            def execute(self, sql: str, params: tuple[object, ...]) -> None:
                self.statements.append((sql, params))

            def fetchone(self):
                return next(self.responses)

        class FakeConnection:
            def __init__(self) -> None:
                self.cursor_instance = FakeCursor()
                self.committed = False

            def cursor(self) -> FakeCursor:
                return self.cursor_instance

            def commit(self) -> None:
                self.committed = True

        connection = FakeConnection()
        MODULE.create_superuser(
            connection,
            tenant_id="openirn-admin",
            tenant_display_name="Administration OpenIRN",
            user_id="11111111-1111-4111-8111-111111111111",
            first_name="Alice",
            last_name="Admin",
            email="alice@example.test",
            pin="84-Delta-29",
        )

        self.assertTrue(connection.committed)
        statements = connection.cursor_instance.statements
        self.assertTrue(any("INSERT INTO users" in sql for sql, _ in statements))
        self.assertTrue(any("requires_change" in sql for sql, _ in statements))
        self.assertTrue(any("bootstrap_administrator_created" in sql for sql, _ in statements))
        self.assertNotIn("84-Delta-29", repr(statements))


if __name__ == "__main__":
    unittest.main()
