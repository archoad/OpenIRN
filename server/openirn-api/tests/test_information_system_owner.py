from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException


APP_DIR = Path(__file__).resolve().parents[1] / "app"
SCHEMA_PATH = Path(__file__).resolve().parents[1] / "sql" / "schema_mariadb.sql"
sys.path.insert(0, str(APP_DIR))

import main as api  # noqa: E402
from database_contract import REQUIRED_MIGRATIONS  # noqa: E402


class InformationSystemOwnerTests(unittest.TestCase):
    def test_schema_contract_declares_structured_owner_identity(self) -> None:
        self.assertEqual(
            REQUIRED_MIGRATIONS[174],
            "information_system_owner_identity",
        )
        schema = SCHEMA_PATH.read_text(encoding="utf-8")
        self.assertIn("owner_first_name VARCHAR(255)", schema)
        self.assertIn("owner_last_name VARCHAR(255)", schema)
        self.assertIn("owner_email VARCHAR(254)", schema)

    def test_structured_owner_is_normalized(self) -> None:
        owner = api._inventory_owner_fields(
            {
                "ownerFirstName": " Alice ",
                "ownerLastName": " Martin ",
                "ownerEmail": " ALICE.MARTIN@EXAMPLE.TEST ",
            }
        )

        self.assertEqual(
            owner,
            (
                "Alice Martin",
                "Alice",
                "Martin",
                "alice.martin@example.test",
            ),
        )

    def test_legacy_owner_is_preserved_as_last_name(self) -> None:
        self.assertEqual(
            api._inventory_owner_fields({"owner": "Porteur historique"}),
            ("Porteur historique", "", "Porteur historique", ""),
        )

    def test_invalid_owner_email_is_rejected(self) -> None:
        with self.assertRaises(HTTPException) as raised:
            api._inventory_owner_fields(
                {
                    "ownerFirstName": "Alice",
                    "ownerLastName": "Martin",
                    "ownerEmail": "invalid",
                }
            )

        self.assertEqual(raised.exception.status_code, 400)

    def test_public_inventory_payload_contains_structured_owner(self) -> None:
        result = api._inventory_row_public(
            {
                "tenant_id": "tenant-a",
                "system_id": "system-a",
                "name": "SI A",
                "description": "Description",
                "owner": "Alice Martin",
                "owner_first_name": "Alice",
                "owner_last_name": "Martin",
                "owner_email": "alice.martin@example.test",
                "created_at": "2026-09-23T00:00:00Z",
                "updated_at": "2026-09-23T00:00:00Z",
            },
            kind="system",
        )

        self.assertEqual(result["ownerFirstName"], "Alice")
        self.assertEqual(result["ownerLastName"], "Martin")
        self.assertEqual(result["ownerEmail"], "alice.martin@example.test")

    def test_migration_adds_columns_backfills_and_records_version(self) -> None:
        statements: list[tuple[str, tuple[object, ...]]] = []

        class Result:
            def fetchone(self):
                return None

        class Connection:
            def execute(self, sql, parameters=None):
                statements.append(
                    (" ".join(sql.split()), tuple(parameters or ()))
                )
                return Result()

        with (
            patch.object(api, "_table_exists", return_value=True),
            patch.object(api, "_table_columns", return_value={"owner"}),
        ):
            api._migrate_information_system_owner_schema(Connection())

        sql_statements = [sql for sql, _parameters in statements]
        self.assertTrue(any("ADD COLUMN owner_first_name" in sql for sql in sql_statements))
        self.assertTrue(any("ADD COLUMN owner_last_name" in sql for sql in sql_statements))
        self.assertTrue(any("ADD COLUMN owner_email" in sql for sql in sql_statements))
        self.assertTrue(
            any(
                "SET owner_last_name = owner" in sql
                for sql in sql_statements
            )
        )
        self.assertTrue(
            any(
                "schema_migrations" in sql
                and parameters == (174, "information_system_owner_identity")
                for sql, parameters in statements
            )
        )

    def test_migration_is_idempotent_when_columns_already_exist(self) -> None:
        statements: list[tuple[str, tuple[object, ...]]] = []

        class Result:
            def fetchone(self):
                return None

        class Connection:
            def execute(self, sql, parameters=None):
                statements.append(
                    (" ".join(sql.split()), tuple(parameters or ()))
                )
                return Result()

        columns = {
            "owner",
            "owner_first_name",
            "owner_last_name",
            "owner_email",
        }
        with (
            patch.object(api, "_table_exists", return_value=True),
            patch.object(api, "_table_columns", return_value=columns),
        ):
            api._migrate_information_system_owner_schema(Connection())
            api._migrate_information_system_owner_schema(Connection())

        sql_statements = [sql for sql, _parameters in statements]
        self.assertFalse(any("ADD COLUMN" in sql for sql in sql_statements))
        self.assertEqual(
            sum("SET owner_last_name = owner" in sql for sql in sql_statements),
            2,
        )
        self.assertEqual(
            sum(
                "schema_migrations" in sql
                and parameters == (174, "information_system_owner_identity")
                for sql, parameters in statements
            ),
            2,
        )


if __name__ == "__main__":
    unittest.main()
