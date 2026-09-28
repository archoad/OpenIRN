from __future__ import annotations

import asyncio
import json
import sqlite3
import sys
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException


APP_DIR = Path(__file__).resolve().parents[1] / "app"
SCHEMA_PATH = Path(__file__).resolve().parents[1] / "sql" / "schema_mariadb.sql"
sys.path.insert(0, str(APP_DIR))

import main as api  # noqa: E402
from database_contract import REQUIRED_MIGRATIONS, REQUIRED_TABLES  # noqa: E402


ASSET_A = "11111111-1111-4111-8111-111111111111"
EVALUATOR_A = "22222222-2222-4222-8222-222222222222"
PILOT_A = "33333333-3333-4333-8333-333333333333"


class _Connection:
    def __init__(self, con: sqlite3.Connection) -> None:
        self.con = con

    def execute(self, sql: str, params: tuple[object, ...] = ()):
        return self.con.execute(sql.replace(" FOR UPDATE", ""), params)

    def __enter__(self):
        self.con.execute("BEGIN")
        return self

    def __exit__(self, exc_type, exc, traceback):
        if exc_type is None:
            self.con.commit()
        else:
            self.con.rollback()
        return False


class _JsonRequest:
    def __init__(self, payload: dict[str, object]) -> None:
        self.payload = payload

    async def json(self) -> dict[str, object]:
        return self.payload


def _database() -> _Connection:
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    con.executescript(
        """
        CREATE TABLE schema_migrations(
            version INTEGER PRIMARY KEY,
            name TEXT NOT NULL
        );
        CREATE TABLE users(
            tenant_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            active INTEGER NOT NULL,
            role TEXT NOT NULL,
            PRIMARY KEY(tenant_id, user_id)
        );
        CREATE TABLE information_assets(
            tenant_id TEXT NOT NULL,
            asset_id TEXT NOT NULL,
            PRIMARY KEY(tenant_id, asset_id)
        );
        CREATE TABLE asset_evaluator_assignments(
            tenant_id TEXT NOT NULL,
            asset_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            assigned_by_user_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(tenant_id, asset_id)
        );
        CREATE TABLE campaign_states(
            tenant_id TEXT NOT NULL,
            campaign_id TEXT NOT NULL,
            received_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            payload_json TEXT NOT NULL
        );
        """
    )
    return _Connection(con)


class AssetEvaluatorAssignmentTests(unittest.TestCase):
    def test_schema_contract_declares_canonical_assignment(self) -> None:
        self.assertIn("asset_evaluator_assignments", REQUIRED_TABLES)
        self.assertEqual(
            REQUIRED_MIGRATIONS[176],
            "canonical_asset_evaluator_assignments",
        )
        schema = SCHEMA_PATH.read_text(encoding="utf-8")
        self.assertIn(
            "CREATE TABLE IF NOT EXISTS asset_evaluator_assignments",
            schema,
        )
        self.assertIn("PRIMARY KEY (tenant_id, asset_id)", schema)

    def test_legacy_assignment_is_backfilled_only_when_unambiguous(self) -> None:
        con = _database()
        self.addCleanup(con.con.close)
        con.execute(
            "INSERT INTO users VALUES (?, ?, 1, 'evaluator')",
            ("tenant-a", EVALUATOR_A),
        )
        con.execute(
            "INSERT INTO information_assets VALUES (?, ?)",
            ("tenant-a", ASSET_A),
        )
        payload = {
            "campaign": {
                "id": "campaign-a",
                "information": {
                    "inventoryScope": {"assets": [{"assetId": ASSET_A}]}
                },
            },
            "assignments": [
                {"criterionId": "RES-1", "userId": EVALUATOR_A},
                {"criterionId": "RES-2", "userId": EVALUATOR_A},
            ],
        }
        con.execute(
            "INSERT INTO campaign_states VALUES (?, ?, ?, ?, ?)",
            (
                "tenant-a",
                "campaign-a",
                "2026-09-01T10:00:00Z",
                "2026-09-01T10:00:00Z",
                json.dumps(payload),
            ),
        )

        with patch.object(api, "_table_exists", return_value=True):
            api._migrate_asset_evaluator_assignments_schema(con)
            api._migrate_asset_evaluator_assignments_schema(con)

        assignment = con.execute(
            "SELECT user_id FROM asset_evaluator_assignments"
        ).fetchone()
        self.assertEqual(assignment["user_id"], EVALUATOR_A)
        migration = con.execute(
            "SELECT name FROM schema_migrations WHERE version = 176"
        ).fetchone()
        self.assertEqual(migration["name"], "canonical_asset_evaluator_assignments")
        migration_count = con.execute(
            "SELECT COUNT(*) FROM schema_migrations WHERE version = 176"
        ).fetchone()[0]
        self.assertEqual(migration_count, 1)

        self.assertEqual(
            api._legacy_campaign_assignment_user_id(
                {
                    "assignments": [
                        {"userId": EVALUATOR_A},
                        {"userId": "another-evaluator"},
                    ]
                }
            ),
            "",
        )

    def test_campaign_read_uses_the_same_assignment_for_the_asset(self) -> None:
        con = _database()
        self.addCleanup(con.con.close)
        con.execute(
            """
            INSERT INTO asset_evaluator_assignments
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                "tenant-a",
                ASSET_A,
                EVALUATOR_A,
                PILOT_A,
                "2026-09-01T10:00:00Z",
                "2026-09-01T10:00:00Z",
            ),
        )
        campaign = {
            "campaign": {
                "id": "campaign-b",
                "referentialId": "ref-a",
                "information": {
                    "inventoryScope": {"assets": [{"assetId": ASSET_A}]}
                },
            },
            "assignments": [{"assetId": "stale", "userId": "stale"}],
        }

        merged = api._campaign_payload_with_canonical_asset_assignments(
            con,
            "tenant-a",
            campaign,
        )

        self.assertEqual(len(merged["assignments"]), 1)
        self.assertEqual(merged["assignments"][0]["assetId"], ASSET_A)
        self.assertEqual(merged["assignments"][0]["userId"], EVALUATOR_A)
        self.assertNotIn(
            "assignments",
            api._campaign_payload_for_storage(campaign),
        )

    def test_migration_does_not_guess_between_conflicting_campaigns(self) -> None:
        con = _database()
        self.addCleanup(con.con.close)
        other_evaluator = "44444444-4444-4444-8444-444444444444"
        for user_id in (EVALUATOR_A, other_evaluator):
            con.execute(
                "INSERT INTO users VALUES (?, ?, 1, 'evaluator')",
                ("tenant-a", user_id),
            )
        con.execute(
            "INSERT INTO information_assets VALUES (?, ?)",
            ("tenant-a", ASSET_A),
        )
        for index, user_id in enumerate((EVALUATOR_A, other_evaluator), start=1):
            payload = {
                "campaign": {
                    "id": f"campaign-{index}",
                    "information": {
                        "inventoryScope": {"assets": [{"assetId": ASSET_A}]}
                    },
                },
                "assignments": [{"criterionId": "RES-1", "userId": user_id}],
            }
            timestamp = f"2026-09-0{index}T10:00:00Z"
            con.execute(
                "INSERT INTO campaign_states VALUES (?, ?, ?, ?, ?)",
                (
                    "tenant-a",
                    f"campaign-{index}",
                    timestamp,
                    timestamp,
                    json.dumps(payload),
                ),
            )

        with patch.object(api, "_table_exists", return_value=True):
            api._migrate_asset_evaluator_assignments_schema(con)

        assignment_count = con.execute(
            "SELECT COUNT(*) FROM asset_evaluator_assignments"
        ).fetchone()[0]
        self.assertEqual(assignment_count, 0)

    def test_only_an_active_evaluator_of_the_tenant_can_be_assigned(self) -> None:
        con = _database()
        self.addCleanup(con.con.close)
        con.execute(
            "INSERT INTO information_assets VALUES (?, ?)",
            ("tenant-a", ASSET_A),
        )
        con.execute(
            "INSERT INTO users VALUES (?, ?, 1, 'evaluator')",
            ("tenant-a", EVALUATOR_A),
        )
        con.execute(
            "INSERT INTO users VALUES (?, ?, 1, 'evaluator')",
            ("tenant-b", PILOT_A),
        )
        con.con.commit()

        @contextmanager
        def database():
            yield con

        auth_context = {
            "userId": PILOT_A,
            "deviceId": "device-a",
            "userRole": "campaign_manager",
            "tenantId": "tenant-a",
        }
        patches = (
            patch.object(api, "_db", database),
            patch.object(
                api,
                "_resolve_tenant_id_for_request",
                side_effect=lambda value, fallback: str(value or fallback),
            ),
            patch.object(
                api,
                "_require_campaign_manager_authorization",
                return_value=auth_context,
            ),
            patch.object(api, "_record_device_audit"),
            patch.object(
                api,
                "_inventory_payload",
                side_effect=lambda _con, tenant_id: {"tenantId": tenant_id},
            ),
        )
        with patches[0], patches[1], patches[2], patches[3], patches[4]:
            result = asyncio.run(
                api.information_asset_evaluator_update(
                    ASSET_A,
                    _JsonRequest(
                        {"tenantId": "tenant-a", "userId": EVALUATOR_A}
                    ),
                )
            )
            self.assertEqual(result["message"], "Évaluateur de l’actif mis à jour")

            stored = con.execute(
                "SELECT user_id FROM asset_evaluator_assignments"
            ).fetchone()
            self.assertEqual(stored["user_id"], EVALUATOR_A)

            with self.assertRaises(HTTPException) as raised:
                asyncio.run(
                    api.information_asset_evaluator_update(
                        ASSET_A,
                        _JsonRequest(
                            {"tenantId": "tenant-a", "userId": PILOT_A}
                        ),
                    )
                )
            self.assertEqual(raised.exception.status_code, 400)


if __name__ == "__main__":
    unittest.main()
