from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch


APP_DIR = Path(__file__).resolve().parents[1] / "app"
SCHEMA_PATH = Path(__file__).resolve().parents[1] / "sql" / "schema_mariadb.sql"
sys.path.insert(0, str(APP_DIR))

import main as api  # noqa: E402
from database_contract import REQUIRED_MIGRATIONS, REQUIRED_TABLES  # noqa: E402


class _Result:
    def __init__(self, rows: list[dict[str, object]] | None = None) -> None:
        self._rows = rows or []

    def fetchall(self) -> list[dict[str, object]]:
        return self._rows

    def fetchone(self) -> dict[str, object] | None:
        return self._rows[0] if self._rows else None


class _CanonicalConnection:
    def __init__(self) -> None:
        self.statements: list[tuple[str, tuple[object, ...]]] = []

    def execute(self, sql: str, params: tuple[object, ...] = ()) -> _Result:
        normalized = " ".join(sql.split())
        self.statements.append((normalized, params))
        if normalized.startswith("SELECT asset_id FROM information_assets"):
            return _Result([{"asset_id": "asset-a"}])
        if normalized.startswith("SELECT answer_json"):
            tenant_id, asset_id, referential_id = params
            if (tenant_id, asset_id, referential_id) == (
                "tenant-a",
                "asset-a",
                "ref-a",
            ):
                return _Result(
                    [
                        {
                            "answer_json": json.dumps(
                                {
                                    "criterionId": "asset:asset-a:criterion:C1",
                                    "answer": "result",
                                }
                            )
                        }
                    ]
                )
        if normalized.startswith("SELECT name, description, owner"):
            return _Result(
                [
                    {
                        "name": "SI courant",
                        "description": "Description courante",
                        "owner": "Alice Martin",
                        "owner_first_name": "Alice",
                        "owner_last_name": "Martin",
                        "owner_email": "alice.martin@example.test",
                    }
                ]
            )
        if normalized.startswith("SELECT a.asset_id"):
            return _Result(
                [
                    {
                        "asset_id": "asset-a",
                        "name": "Base de données",
                        "asset_type": "database",
                        "description": "Partagée",
                        "criticality": "4",
                    }
                ]
            )
        if normalized.startswith("SELECT f.function_id"):
            return _Result(
                [
                    {"function_id": "function-a", "name": "Fonction A"},
                    {"function_id": "function-b", "name": "Fonction B"},
                ]
            )
        return _Result()


class _InventoryConnection:
    def __init__(self) -> None:
        self.statements: list[tuple[str, tuple[object, ...]]] = []

    def execute(self, sql: str, params: tuple[object, ...] = ()) -> _Result:
        normalized = " ".join(sql.split())
        self.statements.append((normalized, params))
        if normalized.startswith("SELECT 1 FROM information_systems"):
            return _Result([{"present": 1}])
        if normalized.startswith("SELECT asset_id, criticality"):
            return _Result(
                [
                    {
                        "asset_id": "11111111-1111-4111-8111-111111111111",
                        "criticality": "4",
                    }
                ]
            )
        return _Result()


class _SharedScoreConnection:
    def __init__(self) -> None:
        self.answers: dict[tuple[str, str, str, str], str] = {}

    def execute(self, sql: str, params: tuple[object, ...] = ()) -> _Result:
        normalized = " ".join(sql.split())
        if normalized.startswith("SELECT asset_id FROM information_assets"):
            return _Result([{"asset_id": "asset-a"}])
        if normalized.startswith("DELETE FROM asset_assessment_answers"):
            tenant_id, asset_id, referential_id = map(str, params)
            self.answers = {
                key: value
                for key, value in self.answers.items()
                if key[:3] != (tenant_id, asset_id, referential_id)
            }
            return _Result()
        if normalized.startswith("INSERT INTO asset_assessment_answers"):
            tenant_id, asset_id, referential_id, criterion_id, answer_json, _, _ = params
            self.answers[
                (
                    str(tenant_id),
                    str(asset_id),
                    str(referential_id),
                    str(criterion_id),
                )
            ] = str(answer_json)
            return _Result()
        if normalized.startswith("SELECT answer_json"):
            tenant_id, asset_id, referential_id = map(str, params)
            rows = [
                {"answer_json": answer_json}
                for key, answer_json in sorted(self.answers.items())
                if key[:3] == (tenant_id, asset_id, referential_id)
            ]
            return _Result(rows)
        return _Result()


def _campaign(*, answers: list[dict[str, object]] | None = None) -> dict[str, object]:
    return {
        "campaign": {
            "id": "campaign-a",
            "referentialId": "ref-a",
            "information": {
                "inventoryScope": {
                    "assets": [
                        {"assetId": "asset-a"},
                        {"assetId": "asset-outside-tenant"},
                    ]
                }
            },
        },
        "answers": answers or [],
    }


class SharedAssetArchitectureTests(unittest.TestCase):
    def test_schema_contract_requires_normalized_links_and_migration(self) -> None:
        self.assertTrue(
            {
                "critical_function_systems",
                "information_system_assets",
                "asset_assessment_answers",
            }.issubset(REQUIRED_TABLES)
        )
        self.assertEqual(
            REQUIRED_MIGRATIONS[173],
            "shared_assets_and_canonical_assessments",
        )
        schema = SCHEMA_PATH.read_text(encoding="utf-8")
        self.assertIn("CREATE TABLE IF NOT EXISTS information_system_assets", schema)
        self.assertIn("CREATE TABLE IF NOT EXISTS asset_assessment_answers", schema)

    def test_campaign_scope_and_answer_identity_are_asset_scoped(self) -> None:
        campaign = _campaign()
        self.assertEqual(
            api._campaign_scope_asset_ids(campaign),
            ["asset-a", "asset-outside-tenant"],
        )
        self.assertEqual(
            api._asset_answer_identity(
                {"criterionId": "asset:asset-a:criterion:C1"}
            ),
            ("asset-a", "C1"),
        )
        self.assertIsNone(api._asset_answer_identity({"criterionId": "C1"}))

    def test_canonical_write_is_limited_to_assets_of_the_tenant(self) -> None:
        con = _CanonicalConnection()
        api._replace_canonical_asset_answers(
            con,
            "tenant-a",
            _campaign(
                answers=[
                    {
                        "criterionId": "asset:asset-a:criterion:C1",
                        "answer": "result",
                    },
                    {
                        "criterionId": "asset:asset-outside-tenant:criterion:C1",
                        "answer": "nonResilient",
                    },
                ]
            ),
            source_campaign_id="campaign-a",
            updated_at="2026-09-11T10:00:00Z",
            replace_existing=True,
        )

        deletes = [item for item in con.statements if item[0].startswith("DELETE")]
        inserts = [
            item
            for item in con.statements
            if item[0].startswith("INSERT INTO asset_assessment_answers")
        ]
        self.assertEqual(len(deletes), 1)
        self.assertEqual(deletes[0][1][1], "asset-a")
        self.assertEqual(len(inserts), 1)
        self.assertEqual(inserts[0][1][1], "asset-a")

    def test_campaign_read_overlays_the_canonical_asset_answer(self) -> None:
        con = _CanonicalConnection()
        merged = api._campaign_payload_with_canonical_asset_answers(
            con,
            "tenant-a",
            _campaign(
                answers=[
                    {
                        "criterionId": "asset:asset-a:criterion:C1",
                        "answer": "nonResilient",
                    },
                    {"criterionId": "legacy-C2", "answer": "intention"},
                ]
            ),
        )

        self.assertEqual(
            merged["answers"],
            [
                {"criterionId": "legacy-C2", "answer": "intention"},
                {
                    "criterionId": "asset:asset-a:criterion:C1",
                    "answer": "result",
                },
            ],
        )

    def test_score_written_in_campaign_a_is_read_in_campaign_b(self) -> None:
        con = _SharedScoreConnection()
        campaign_a = _campaign(
            answers=[
                {
                    "criterionId": "asset:asset-a:criterion:C1",
                    "answer": "result",
                    "justification": "Contrôle en place",
                }
            ]
        )
        api._replace_canonical_asset_answers(
            con,
            "tenant-a",
            campaign_a,
            source_campaign_id="campaign-a",
            updated_at="2026-09-11T10:00:00Z",
            replace_existing=True,
        )

        campaign_b = _campaign()
        campaign_b["campaign"]["id"] = "campaign-b"
        merged = api._campaign_payload_with_canonical_asset_answers(
            con,
            "tenant-a",
            campaign_b,
        )

        self.assertEqual(len(merged["answers"]), 1)
        self.assertEqual(merged["answers"][0]["answer"], "result")
        self.assertEqual(
            merged["answers"][0]["justification"],
            "Contrôle en place",
        )

    def test_campaign_read_refreshes_current_system_scope(self) -> None:
        con = _CanonicalConnection()
        campaign = _campaign()
        campaign_record = campaign["campaign"]
        assert isinstance(campaign_record, dict)
        information = campaign_record["information"]
        assert isinstance(information, dict)
        information["systemName"] = "Ancien SI"
        information["systemDescription"] = "Ancienne description"
        information["projectDirectorFirstName"] = "Ancien"
        information["projectDirectorLastName"] = "Responsable"
        information["projectDirectorEmail"] = "ancien@example.test"
        scope = information["inventoryScope"]
        assert isinstance(scope, dict)
        scope["informationSystemId"] = "system-a"
        scope["assets"] = []

        merged = api._campaign_payload_with_canonical_asset_answers(
            con,
            "tenant-a",
            campaign,
        )
        merged_campaign = merged["campaign"]
        assert isinstance(merged_campaign, dict)
        merged_information = merged_campaign["information"]
        assert isinstance(merged_information, dict)
        merged_scope = merged_information["inventoryScope"]
        assert isinstance(merged_scope, dict)

        self.assertEqual(merged_information["systemName"], "SI courant")
        self.assertEqual(
            merged_information["systemDescription"],
            "Description courante",
        )
        self.assertEqual(
            merged_information["projectDirectorFirstName"],
            "Alice",
        )
        self.assertEqual(
            merged_information["projectDirectorLastName"],
            "Martin",
        )
        self.assertEqual(
            merged_information["projectDirectorEmail"],
            "alice.martin@example.test",
        )
        self.assertEqual(
            merged_scope["criticalFunctionIds"],
            ["function-a", "function-b"],
        )
        self.assertEqual(merged_scope["criticalFunctionName"], "Fonction A, Fonction B")
        self.assertEqual(merged_scope["assets"][0]["assetId"], "asset-a")
        self.assertEqual(
            merged["answers"][0]["criterionId"],
            "asset:asset-a:criterion:C1",
        )
        system_queries = [
            parameters
            for statement, parameters in con.statements
            if statement.startswith("SELECT name, description, owner")
        ]
        self.assertEqual(system_queries, [("tenant-a", "system-a")])

    def test_transient_replace_marker_is_not_stored_in_campaign_history(self) -> None:
        stored = api._campaign_payload_for_storage(
            {
                "expectedServerRevision": 3,
                "replaceAssetAnswers": True,
                "campaign": {"id": "campaign-a"},
            }
        )
        self.assertNotIn("expectedServerRevision", stored)
        self.assertNotIn("replaceAssetAnswers", stored)

    def test_excel_round_trip_replaces_links_without_deleting_global_assets(self) -> None:
        con = _InventoryConnection()
        with patch.object(
            api,
            "_inventory_system_export_context",
            return_value=(
                {"functionId": "function-a", "name": "Fonction A"},
                {"systemId": "system-a", "name": "SI A"},
                [
                    {
                        "assetId": "11111111-1111-4111-8111-111111111111",
                        "name": "Base de données",
                        "assetType": "database",
                        "criticality": "4",
                        "description": "Partagée",
                    }
                ],
            ),
        ):
            raw = api._inventory_to_excel_bytes(con, "tenant-a", "system-a")

        counts = api._inventory_import_from_excel_bytes(
            con,
            "tenant-a",
            "system-a",
            raw,
        )

        self.assertEqual(counts, {"assets": 1})
        sql = [statement for statement, _ in con.statements]
        self.assertIn(
            "DELETE FROM information_system_assets WHERE tenant_id = ? AND system_id = ?",
            sql,
        )
        self.assertFalse(
            any(
                statement.startswith("DELETE FROM information_assets")
                for statement in sql
            )
        )
        self.assertTrue(
            any(
                statement.startswith("INSERT INTO information_system_assets")
                for statement in sql
            )
        )


if __name__ == "__main__":
    unittest.main()
