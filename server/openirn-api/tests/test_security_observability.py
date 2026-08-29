from __future__ import annotations

import json
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from fastapi import HTTPException

APP_DIR = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP_DIR))

import main as api  # noqa: E402
import observability  # noqa: E402

HASH_SECRET = "openirn-observability-test-secret-0001"


class _QueuedConnection:
    def __init__(self):
        self.events: list[dict[str, object]] = []
        self.statements: list[tuple[str, tuple[object, ...]]] = []

    def execute(self, sql, parameters=None):
        self.statements.append((" ".join(sql.split()), tuple(parameters or ())))
        return Mock()

    def queue_security_event(self, event):
        self.events.append(event)


class _Request:
    def __init__(self):
        self.headers: dict[str, str] = {}
        self.client = type("Client", (), {"host": "192.0.2.77"})()


class SecurityEventPrivacyTests(unittest.TestCase):
    def test_security_event_pseudonymizes_identifiers_and_drops_unknown_fields(self):
        raw_values = {
            "tenant": "tenant-private-17",
            "target_tenant": "tenant-private-18",
            "actor": "user-private-21",
            "target_user": "user-private-22",
            "device": "device-private-23",
            "session": "session-private-24",
            "enrollment": "enrollment-private-25",
            "request": "request-private-26",
            "address": "192.0.2.88",
            "pin": "7391-private-pin",
            "email": "alice@example.invalid",
        }
        with patch.dict(
            os.environ,
            {observability.OBSERVABILITY_HASH_SECRET_ENV: HASH_SECRET},
        ):
            event = observability.build_security_event(
                "user.directory_replaced",
                service_version="test",
                tenant_id=raw_values["tenant"],
                target_tenant_id=raw_values["target_tenant"],
                actor_user_id=raw_values["actor"],
                target_user_id=raw_values["target_user"],
                device_id=raw_values["device"],
                session_id=raw_values["session"],
                enrollment_id=raw_values["enrollment"],
                request_id=raw_values["request"],
                source_address=raw_values["address"],
                reason="directory_update",
                attributes={
                    "createdCount": 2,
                    "administratorGrantedCount": 1,
                    "operation": "replace",
                    "pin": raw_values["pin"],
                    "email": raw_values["email"],
                },
            )

        serialized = json.dumps(event, sort_keys=True)
        for raw_value in raw_values.values():
            self.assertNotIn(raw_value, serialized)
        self.assertEqual(event["event"]["dataset"], "openirn.security")
        self.assertEqual(event["event"]["outcome"], "success")
        self.assertEqual(
            event["openirn"]["security"]["attributes"],
            {
                "administrator_granted_count": 1,
                "created_count": 2,
                "operation": "replace",
            },
        )

    def test_pseudonyms_are_stable_per_secret_and_change_after_rotation(self):
        def organization_id(secret: str) -> str:
            with patch.dict(
                os.environ,
                {observability.OBSERVABILITY_HASH_SECRET_ENV: secret},
            ):
                return observability.build_security_event(
                    "session.created",
                    service_version="test",
                    tenant_id="tenant-a",
                )["organization"]["id"]

        first = organization_id(HASH_SECRET)
        self.assertEqual(first, organization_id(HASH_SECRET))
        self.assertNotEqual(first, organization_id(HASH_SECRET + "-rotated"))

    def test_missing_hash_secret_omits_identifiers_instead_of_logging_them(self):
        with patch.dict(os.environ, {}, clear=True):
            event = observability.build_security_event(
                "session.created",
                service_version="test",
                tenant_id="tenant-private",
                actor_user_id="user-private",
                source_address="192.0.2.44",
            )

        self.assertNotIn("organization", event)
        self.assertNotIn("user", event)
        self.assertNotIn("openirn", event)
        self.assertNotIn("tenant-private", json.dumps(event))


class CommittedSecurityEventTests(unittest.TestCase):
    def test_commit_emits_queued_events_after_mariadb_commit(self):
        sequence: list[str] = []
        connection = api._MySQLConnection.__new__(api._MySQLConnection)
        connection._pending_security_events = [{"event": {"action": "session.created"}}]
        connection._con = Mock()
        connection._con.commit.side_effect = lambda: sequence.append("commit")

        with patch.object(
            api,
            "emit_security_event",
            side_effect=lambda event: sequence.append("emit"),
        ) as emit:
            connection.commit()

        self.assertEqual(sequence, ["commit", "emit"])
        emit.assert_called_once()
        self.assertEqual(connection._pending_security_events, [])

    def test_rollback_discards_queued_events(self):
        connection = api._MySQLConnection.__new__(api._MySQLConnection)
        connection._pending_security_events = [{"event": {"action": "session.created"}}]
        connection._con = Mock()

        with patch.object(api, "emit_security_event") as emit:
            connection.rollback()

        connection._con.rollback.assert_called_once()
        emit.assert_not_called()
        self.assertEqual(connection._pending_security_events, [])

    def test_auth_attempt_queues_one_pseudonymized_event(self):
        connection = _QueuedConnection()
        with patch.dict(
            os.environ,
            {observability.OBSERVABILITY_HASH_SECRET_ENV: HASH_SECRET},
        ):
            api._record_auth_attempt(
                connection,
                "tenant-private",
                device_id="device-private",
                user_id="user-private",
                ip_address="192.0.2.45",
                successful=False,
                reason="invalid_pin",
            )

        self.assertEqual(len(connection.events), 1)
        event = connection.events[0]
        self.assertEqual(event["event"]["action"], "auth.failed")
        self.assertEqual(event["event"]["outcome"], "failure")
        serialized = json.dumps(event)
        for raw_value in (
            "tenant-private",
            "device-private",
            "user-private",
            "192.0.2.45",
        ):
            self.assertNotIn(raw_value, serialized)

    def test_device_audit_only_queues_security_events_without_auth_duplicate(self):
        connection = _QueuedConnection()
        with patch.dict(
            os.environ,
            {observability.OBSERVABILITY_HASH_SECRET_ENV: HASH_SECRET},
        ):
            api._record_device_audit(connection, "tenant-a", "inventory.received")
            api._record_device_audit(connection, "tenant-a", "auth.failed")
            api._record_device_audit(
                connection,
                "tenant-a",
                "user.initial_pin_created",
                payload={"userId": "user-a"},
            )

        self.assertEqual(len(connection.events), 1)
        self.assertEqual(
            connection.events[0]["event"]["action"],
            "user.initial_pin_created",
        )


class SecurityAuditCoverageTests(unittest.TestCase):
    def test_cross_tenant_denial_is_emitted_without_raw_identifiers(self):
        request = _Request()
        context = {
            "authMode": "session",
            "tenantId": "tenant-private-a",
            "userId": "user-private-a",
            "deviceId": "device-private-a",
            "userRole": "administrator",
        }
        with (
            patch.dict(
                os.environ,
                {observability.OBSERVABILITY_HASH_SECRET_ENV: HASH_SECRET},
            ),
            patch.object(api, "_request_auth_context", return_value=context),
            patch.object(api, "emit_security_event") as emit,
        ):
            with self.assertRaises(HTTPException):
                api._require_admin_authorization(request, "tenant-private-b")

        event = emit.call_args.args[0]
        self.assertEqual(event["event"]["action"], "authorization.denied")
        self.assertEqual(event["openirn"]["security"]["reason"], "tenant_mismatch")
        serialized = json.dumps(event)
        for raw_value in (
            "tenant-private-a",
            "tenant-private-b",
            "user-private-a",
            "device-private-a",
            "192.0.2.77",
        ):
            self.assertNotIn(raw_value, serialized)

    def test_user_directory_summary_tracks_privilege_changes_without_pii(self):
        existing = [
            {
                "id": "kept-admin",
                "firstName": "Alice",
                "lastName": "Admin",
                "email": "alice@example.invalid",
                "role": "administrator",
                "active": True,
            },
            {
                "id": "promoted-user",
                "firstName": "Bob",
                "lastName": "Pilot",
                "email": "bob@example.invalid",
                "role": "campaign_manager",
                "active": True,
            },
            {
                "id": "deleted-admin",
                "firstName": "Deleted",
                "lastName": "Admin",
                "email": "deleted@example.invalid",
                "role": "administrator",
                "active": True,
            },
        ]
        replacement = [
            existing[0],
            {
                **existing[1],
                "role": "administrator",
            },
            {
                "id": "created-reader",
                "firstName": "Carol",
                "lastName": "Reader",
                "email": "carol@example.invalid",
                "role": "reader",
                "active": True,
            },
        ]

        summary = api._user_directory_change_summary(existing, replacement)

        self.assertEqual(
            summary,
            {
                "createdCount": 1,
                "updatedCount": 1,
                "deletedCount": 1,
                "roleChangedCount": 1,
                "activationChangedCount": 0,
                "administratorCount": 2,
                "administratorGrantedCount": 1,
                "administratorRevokedCount": 1,
            },
        )
        self.assertNotIn("@", json.dumps(summary))


if __name__ == "__main__":
    unittest.main()
