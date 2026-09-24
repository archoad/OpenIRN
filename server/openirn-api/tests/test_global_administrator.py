from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch


APP_DIR = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP_DIR))

import main as api  # noqa: E402
from database_contract import REQUIRED_MIGRATIONS  # noqa: E402
from fastapi import HTTPException  # noqa: E402


class _Result:
    def __init__(self, *, rows=None):
        self._rows = list(rows or [])

    def fetchall(self):
        return list(self._rows)

    def fetchone(self):
        return self._rows[0] if self._rows else None


class _MigrationConnection:
    def __init__(self):
        self.statements: list[tuple[str, tuple[object, ...]]] = []

    def execute(self, sql, parameters=None):
        normalized = " ".join(sql.split())
        values = tuple(parameters or ())
        self.statements.append((normalized, values))
        if normalized.startswith("SELECT tenant_id, user_id, active FROM users"):
            return _Result(
                rows=[
                    {
                        "tenant_id": "admin-space",
                        "user_id": "global-admin",
                        "active": 1,
                    },
                    {
                        "tenant_id": "tenant-a",
                        "user_id": "global-admin",
                        "active": 1,
                    },
                    {
                        "tenant_id": "tenant-a",
                        "user_id": "legacy-local-admin",
                        "active": 1,
                    },
                    {
                        "tenant_id": "tenant-b",
                        "user_id": "inactive-local-admin",
                        "active": 0,
                    },
                ]
            )
        return _Result()


class GlobalAdministratorMigrationTests(unittest.TestCase):
    def test_contract_requires_global_administrator_migration(self):
        self.assertEqual(REQUIRED_MIGRATIONS[175], "global_administrator_role")

    def test_migration_deletes_only_legacy_local_administrators(self):
        connection = _MigrationConnection()
        with (
            patch.object(api, "_migration_applied", return_value=False),
            patch.object(api, "_resolve_tenant_id", return_value="admin-space"),
            patch.object(api, "_sync_global_administrators_to_all_tenants") as sync,
            patch.object(api, "_record_device_audit") as audit,
            patch.object(api, "_record_migration") as record,
        ):
            api._migrate_global_administrator_role(connection)

        deleted_sessions = [
            parameters
            for statement, parameters in connection.statements
            if statement.startswith("DELETE FROM api_sessions")
        ]
        deleted_users = [
            parameters
            for statement, parameters in connection.statements
            if statement.startswith("DELETE FROM users")
        ]
        self.assertEqual(
            deleted_sessions,
            [
                ("tenant-a", "legacy-local-admin"),
                ("tenant-b", "inactive-local-admin"),
            ],
        )
        self.assertEqual(
            deleted_users,
            [
                ("tenant-a", "legacy-local-admin"),
                ("tenant-b", "inactive-local-admin"),
            ],
        )
        self.assertEqual(audit.call_count, 2)
        self.assertEqual(
            audit.call_args.args[2],
            "user.legacy_local_administrator_deleted",
        )
        sync.assert_called_once_with(connection)
        record.assert_called_once_with(connection, 175, "global_administrator_role")

    def test_migration_refuses_to_delete_without_a_global_administrator(self):
        connection = _MigrationConnection()
        connection.execute = lambda sql, parameters=None: _Result(
            rows=[
                {
                    "tenant_id": "tenant-a",
                    "user_id": "legacy-local-admin",
                    "active": 1,
                }
            ]
        )
        with (
            patch.object(api, "_migration_applied", return_value=False),
            patch.object(api, "_resolve_tenant_id", return_value="admin-space"),
        ):
            with self.assertRaisesRegex(RuntimeError, "aucun Administrateur global"):
                api._migrate_global_administrator_role(connection)

    def test_migration_refuses_to_choose_between_global_administrators(self):
        connection = _MigrationConnection()
        connection.execute = lambda sql, parameters=None: _Result(
            rows=[
                {
                    "tenant_id": "admin-space",
                    "user_id": "global-admin-a",
                    "active": 1,
                },
                {
                    "tenant_id": "admin-space",
                    "user_id": "global-admin-b",
                    "active": 1,
                },
            ]
        )
        with (
            patch.object(api, "_migration_applied", return_value=False),
            patch.object(api, "_resolve_tenant_id", return_value="admin-space"),
        ):
            with self.assertRaisesRegex(RuntimeError, "plusieurs Administrateurs"):
                api._migrate_global_administrator_role(connection)


class GlobalAdministratorDirectoryTests(unittest.TestCase):
    def setUp(self):
        self.global_administrator = {
            "id": "global-admin",
            "firstName": "Global",
            "lastName": "Administrator",
            "email": "admin@example.org",
            "role": "administrator",
            "active": True,
        }

    def test_pilot_can_retain_the_unchanged_global_administrator(self):
        api._validate_global_administrator_directory_change(
            [self.global_administrator],
            [dict(self.global_administrator)],
            protected_ids={"global-admin"},
            caller_is_administrator=False,
        )

    def test_pilot_cannot_modify_the_global_administrator(self):
        changed = {**self.global_administrator, "email": "changed@example.org"}
        with self.assertRaises(HTTPException) as raised:
            api._validate_global_administrator_directory_change(
                [self.global_administrator],
                [changed],
                protected_ids={"global-admin"},
                caller_is_administrator=False,
            )
        self.assertEqual(raised.exception.status_code, 403)

    def test_administrator_cannot_create_another_administrator(self):
        second_administrator = {
            **self.global_administrator,
            "id": "second-admin",
            "email": "second@example.org",
        }
        with self.assertRaises(HTTPException) as raised:
            api._validate_global_administrator_directory_change(
                [self.global_administrator],
                [self.global_administrator, second_administrator],
                protected_ids={"global-admin"},
                caller_is_administrator=True,
            )
        self.assertEqual(raised.exception.status_code, 403)


if __name__ == "__main__":
    unittest.main()
