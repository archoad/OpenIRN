from __future__ import annotations

import json
import sys
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException


APP_DIR = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP_DIR))

import main as api  # noqa: E402


class _Result:
    def __init__(self, *, one=None, many=None):
        self._one = one
        self._many = list(many or [])

    def fetchone(self):
        return self._one

    def fetchall(self):
        return list(self._many)


class _CampaignRevisionConnection:
    def __init__(self, states=None):
        self.states = dict(states or {})
        self.revisions = []
        self.statements = []

    def execute(self, sql, parameters=None):
        normalized = " ".join(sql.split())
        parameters = tuple(parameters or ())
        self.statements.append((normalized, parameters))

        if normalized.startswith("SELECT server_revision"):
            campaign_id = parameters[1]
            return _Result(one=self.states.get(campaign_id))
        if normalized.startswith("INSERT INTO campaign_revisions"):
            self.revisions.append(parameters)
            return _Result()
        if normalized.startswith("INSERT INTO campaign_states"):
            campaign_id = parameters[1]
            self.states[campaign_id] = {
                "server_revision": parameters[2],
                "payload_sha256": parameters[7],
                "device_id": parameters[4],
                "received_at": parameters[6],
                "payload_json": parameters[8],
            }
            return _Result()
        if normalized.startswith("INSERT INTO sync_events"):
            return _Result()
        raise AssertionError(f"Unexpected SQL in revision test: {normalized}")


class _DeleteConnection:
    def __init__(self, states):
        self.states = dict(states)
        self.statements = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return None

    def execute(self, sql, parameters=None):
        normalized = " ".join(sql.split())
        parameters = tuple(parameters or ())
        self.statements.append((normalized, parameters))
        if normalized.startswith("SELECT campaign_id, server_revision"):
            return _Result(one=self.states.get(parameters[1]))
        if normalized.startswith("DELETE FROM campaign_states"):
            self.states.pop(parameters[1], None)
            return _Result()
        if normalized.startswith("SELECT payload_json FROM campaign_states"):
            rows = [
                {"payload_json": state["payload_json"]}
                for _, state in sorted(self.states.items())
            ]
            return _Result(many=rows)
        if normalized.startswith("INSERT INTO sync_snapshots"):
            return _Result()
        if normalized.startswith("INSERT INTO sync_events"):
            return _Result()
        if normalized.startswith("INSERT INTO device_audit_log"):
            return _Result()
        raise AssertionError(f"Unexpected SQL in delete test: {normalized}")


@contextmanager
def _database(connection):
    yield connection


class CampaignOptimisticConcurrencyTests(unittest.TestCase):
    campaign_id = "11111111-1111-4111-8111-111111111111"
    other_campaign_id = "22222222-2222-4222-8222-222222222222"

    def _campaign(self, name, expected_revision=None):
        item = {
            "campaign": {
                "id": self.campaign_id,
                "name": name,
                "updatedAt": "2026-08-24T10:00:00Z",
            },
            "answers": [],
        }
        if expected_revision is not None:
            item["expectedServerRevision"] = expected_revision
        return item

    def _state(self, campaign, revision):
        stored = api._campaign_payload_for_storage(campaign)
        return {
            "server_revision": revision,
            "payload_sha256": api._json_sha256(stored),
            "device_id": "device-a",
            "received_at": "2026-08-24T09:00:00Z",
            "payload_json": api._canonical_json(stored),
        }

    def test_existing_campaign_requires_expected_revision(self):
        existing = self._campaign("Initial", expected_revision=2)
        connection = _CampaignRevisionConnection(
            {self.campaign_id: self._state(existing, 2)}
        )

        with self.assertRaises(HTTPException) as raised:
            api._record_campaign_revisions(
                connection,
                "tenant-a",
                "sync-1",
                "device-b",
                "2026-08-24T10:00:00Z",
                {"campaigns": [self._campaign("Changed")]},
            )

        self.assertEqual(raised.exception.status_code, 428)
        self.assertEqual(connection.revisions, [])

    def test_stale_revision_is_rejected_without_overwrite(self):
        existing = self._campaign("Current", expected_revision=3)
        connection = _CampaignRevisionConnection(
            {self.campaign_id: self._state(existing, 3)}
        )

        with self.assertRaises(HTTPException) as raised:
            api._record_campaign_revisions(
                connection,
                "tenant-a",
                "sync-2",
                "device-b",
                "2026-08-24T10:00:00Z",
                {"campaigns": [self._campaign("Stale change", expected_revision=2)]},
            )

        self.assertEqual(raised.exception.status_code, 409)
        self.assertEqual(connection.states[self.campaign_id]["server_revision"], 3)
        self.assertEqual(connection.revisions, [])

    def test_matching_revision_updates_only_present_campaigns(self):
        current = self._campaign("Current", expected_revision=2)
        other_payload = {
            "campaign": {"id": self.other_campaign_id, "name": "Other"},
            "answers": [],
        }
        connection = _CampaignRevisionConnection(
            {
                self.campaign_id: self._state(current, 2),
                self.other_campaign_id: self._state(other_payload, 7),
            }
        )

        result = api._record_campaign_revisions(
            connection,
            "tenant-a",
            "sync-3",
            "device-b",
            "2026-08-24T10:00:00Z",
            {"campaigns": [self._campaign("Updated", expected_revision=2)]},
        )

        self.assertEqual(result["revisionCount"], 1)
        self.assertEqual(result["deletedCount"], 0)
        self.assertEqual(connection.states[self.campaign_id]["server_revision"], 3)
        self.assertIn(self.other_campaign_id, connection.states)
        stored_payload = json.loads(connection.states[self.campaign_id]["payload_json"])
        self.assertNotIn("expectedServerRevision", stored_payload)
        self.assertFalse(
            any(statement.startswith("DELETE FROM") for statement, _ in connection.statements)
        )


class CampaignDeleteTests(unittest.TestCase):
    def test_delete_is_explicit_revision_checked_and_preserves_history(self):
        campaign_id = "33333333-3333-4333-8333-333333333333"
        connection = _DeleteConnection(
            {
                campaign_id: {
                    "campaign_id": campaign_id,
                    "server_revision": 4,
                    "payload_json": json.dumps(
                        {"campaign": {"id": campaign_id, "name": "Delete me"}}
                    ),
                }
            }
        )

        with (
            patch.object(api, "_resolve_tenant_id_for_request", return_value="tenant-a"),
            patch.object(
                api,
                "_require_campaign_manager_authorization",
                return_value={"deviceId": "device-a", "userId": "user-a"},
            ),
            patch.object(api, "_db", return_value=_database(connection)),
        ):
            response = api.campaign_delete(
                campaign_id,
                object(),
                tenantId="tenant-a",
                expectedRevision=4,
            )

        self.assertEqual(response["status"], "deleted")
        self.assertNotIn(campaign_id, connection.states)
        self.assertTrue(response["revisionHistoryPreserved"])
        self.assertFalse(
            any(
                "DELETE FROM campaign_revisions" in statement
                for statement, _ in connection.statements
            )
        )


class TenantDiscoveryTests(unittest.TestCase):
    def test_public_discovery_is_read_only_and_minimal(self):
        connection = object()
        rich_tenant = {
            "tenantId": "tenant-a",
            "id": "tenant-a",
            "displayName": "Tenant A",
            "description": "Internal description",
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-02T00:00:00Z",
            "userCount": 5,
            "activeUserCount": 4,
            "administratorCount": 1,
            "campaignCount": 3,
            "permanent": False,
            "isDefault": False,
        }

        with (
            patch.object(api, "_resolve_tenant_id_for_request", return_value="unknown"),
            patch.object(api, "_request_has_solution_admin_authorization", return_value=False),
            patch.object(api, "_list_tenants", return_value=[rich_tenant]),
            patch.object(api, "_db", return_value=_database(connection)),
        ):
            response = api.tenants(object(), tenantId="unknown")

        self.assertEqual(response["tenantId"], "unknown")
        self.assertNotIn("solutionAdminTenantId", response)
        self.assertEqual(
            set(response["tenants"][0]),
            {"tenantId", "id", "displayName", "permanent", "isDefault"},
        )


if __name__ == "__main__":
    unittest.main()
