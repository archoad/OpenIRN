from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from fastapi import HTTPException


APP_DIR = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP_DIR))

import main as api  # noqa: E402


class _Request:
    def __init__(self, payload: dict[str, object] | None = None):
        self._payload = payload or {}
        self.headers: dict[str, str] = {}
        self.client = type("Client", (), {"host": "127.0.0.1"})()

    async def json(self) -> dict[str, object]:
        return dict(self._payload)


class _Connection:
    def __init__(self):
        self.statements: list[tuple[str, tuple[object, ...]]] = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return None

    def execute(self, sql, parameters=None):
        self.statements.append((" ".join(sql.split()), tuple(parameters or ())))
        return type("Result", (), {"fetchone": lambda self: None, "fetchall": lambda self: []})()

    def commit(self):
        return None


class _PinConnection(_Connection):
    def execute(self, sql, parameters=None):
        normalized = " ".join(sql.split())
        self.statements.append((normalized, tuple(parameters or ())))
        user_exists = normalized.startswith("SELECT 1 FROM users")
        row = {"exists": 1} if user_exists else None
        return type(
            "Result",
            (),
            {
                "fetchone": lambda self: row,
                "fetchall": lambda self: [],
            },
        )()


class DeviceAuthorizationTests(unittest.TestCase):
    def test_public_device_id_no_longer_grants_tenant_read(self):
        with patch.object(api, "_request_auth_context", return_value=None):
            with self.assertRaises(HTTPException) as raised:
                api._require_device_or_authorized_read(_Request(), "tenant-a")

        self.assertEqual(raised.exception.status_code, 403)

    def test_only_flagged_solution_administrator_is_global(self):
        local_administrator = {
            "authMode": "session",
            "tenantId": "tenant-a",
            "userRole": "administrator",
        }
        solution_administrator = {
            **local_administrator,
            "solutionAdministrator": True,
        }

        self.assertFalse(api._is_solution_admin_context(local_administrator))
        self.assertTrue(api._is_solution_admin_context(solution_administrator))

    def test_local_administrator_cannot_cross_tenant_boundary(self):
        context = {
            "authMode": "session",
            "tenantId": "tenant-a",
            "userRole": "administrator",
        }
        with patch.object(api, "_request_auth_context", return_value=context):
            with self.assertRaises(HTTPException) as raised:
                api._require_admin_authorization(_Request(), "tenant-b")

        self.assertEqual(raised.exception.status_code, 403)

    def test_global_legacy_bearer_no_longer_grants_tenant_read(self):
        context = {"authMode": "legacy_global_bearer", "tenantId": ""}
        with patch.object(api, "_request_auth_context", return_value=context):
            with self.assertRaises(HTTPException) as raised:
                api._require_device_or_authorized_read(_Request(), "tenant-a")

        self.assertEqual(raised.exception.status_code, 403)

    def test_device_token_is_bound_to_tenant_and_device_id(self):
        request = _Request({"deviceId": "device-b"})
        context = {
            "authMode": "legacy_device_token",
            "tenantId": "tenant-a",
            "deviceId": "device-a",
        }
        with patch.object(api, "_request_auth_context", return_value=context):
            with self.assertRaises(HTTPException) as raised:
                api._require_device_token_authorization(request, "tenant-a", request._payload)

        self.assertEqual(raised.exception.status_code, 403)


class PinPolicyTests(unittest.TestCase):
    def test_predictable_pins_are_rejected(self):
        for pin in ("0000", "1234", "9876", "aaaa"):
            with self.subTest(pin=pin), self.assertRaises(HTTPException):
                api._validate_new_pin(pin)

    def test_non_trivial_pin_is_accepted(self):
        self.assertEqual(api._validate_new_pin("7391"), "7391")

    def test_current_pin_cannot_be_reused(self):
        with self.assertRaises(HTTPException):
            api._validate_new_pin("7391", current_pin="7391")

    def test_solution_administrator_pin_is_identical_in_every_tenant(self):
        connection = _PinConnection()
        with patch.object(
            api,
            "_user_pin_scope_tenant_ids",
            return_value=["tenant-a", "tenant-b"],
        ):
            affected = api._set_user_pin(
                connection,
                "tenant-a",
                "admin-a",
                "8462",
                requires_change=False,
            )

        inserts = [
            parameters
            for statement, parameters in connection.statements
            if statement.startswith("INSERT INTO user_credentials")
        ]
        self.assertEqual(affected, ["tenant-a", "tenant-b"])
        self.assertEqual(len(inserts), 2)
        self.assertEqual(inserts[0][0:2], ("tenant-a", "admin-a"))
        self.assertEqual(inserts[1][0:2], ("tenant-b", "admin-a"))
        self.assertEqual(inserts[0][2:], inserts[1][2:])

    def test_matching_user_id_without_administrator_role_stays_local(self):
        connection = MagicMock()
        connection.execute.return_value.fetchone.return_value = {
            "active": 1,
            "role": "campaign_manager",
        }
        with patch.object(api, "_solution_administrator_tenant_ids") as global_scope:
            affected = api._user_pin_scope_tenant_ids(
                connection,
                "tenant-a",
                "shared-id",
            )

        self.assertEqual(affected, ["tenant-a"])
        global_scope.assert_not_called()


class AuthenticationFlowTests(unittest.IsolatedAsyncioTestCase):
    async def test_temporary_pin_does_not_create_full_session(self):
        connection = _Connection()
        request = _Request(
            {"tenantId": "tenant-a", "deviceId": "device-a", "userId": "user-a", "pin": "7391"}
        )
        user = {"id": "user-a", "active": True, "role": "evaluator"}

        with (
            patch.object(
                api,
                "_require_device_token_authorization",
                return_value={"deviceId": "device-a"},
            ),
            patch.object(api, "_db", return_value=connection),
            patch.object(api, "_ensure_tenant"),
            patch.object(api, "_enforce_auth_rate_limit"),
            patch.object(api, "_load_central_users", return_value=[user]),
            patch.object(api, "_ensure_user_credentials"),
            patch.object(api, "_verify_user_pin", return_value=(True, True)),
            patch.object(api, "_record_device_audit"),
            patch.object(api, "_create_api_session") as create_session,
        ):
            with self.assertRaises(HTTPException) as raised:
                await api.auth_verify(request)

        self.assertEqual(raised.exception.status_code, 428)
        self.assertEqual(raised.exception.detail["code"], "pin_change_required")
        create_session.assert_not_called()

    async def test_replacing_temporary_pin_creates_session_after_change(self):
        connection = _Connection()
        request = _Request(
            {
                "tenantId": "tenant-a",
                "deviceId": "device-a",
                "userId": "user-a",
                "pin": "7391",
                "newPin": "8462",
            }
        )
        user = {"id": "user-a", "active": True, "role": "evaluator"}

        with (
            patch.object(
                api,
                "_require_device_token_authorization",
                return_value={"deviceId": "device-a"},
            ),
            patch.object(api, "_db", return_value=connection),
            patch.object(api, "_ensure_tenant"),
            patch.object(api, "_enforce_auth_rate_limit"),
            patch.object(api, "_load_central_users", return_value=[user]),
            patch.object(api, "_ensure_user_credentials"),
            patch.object(api, "_verify_user_pin", return_value=(True, True)),
            patch.object(api, "_set_user_pin") as set_pin,
            patch.object(api, "_record_auth_attempt"),
            patch.object(api, "_record_device_audit"),
            patch.object(
                api,
                "_create_api_session",
                return_value=("session-a", "ost_secret", api._utc_now()),
            ),
        ):
            response = await api.auth_verify(request)

        set_pin.assert_called_once_with(
            connection,
            "tenant-a",
            "user-a",
            "8462",
            requires_change=False,
        )
        self.assertEqual(response["apiToken"], "ost_secret")
        self.assertFalse(response["mustChangePin"])

    async def test_administrator_reset_is_temporary_and_revokes_sessions(self):
        connection = _Connection()
        request = _Request(
            {"tenantId": "tenant-a", "userId": "user-a", "pin": "8462"}
        )
        context = {
            "deviceId": "device-admin",
            "userId": "admin-a",
            "userRole": "administrator",
        }

        with (
            patch.object(api, "_require_admin_authorization", return_value=context) as authorize,
            patch.object(api, "_create_protective_backup", return_value={}),
            patch.object(api, "_db", return_value=connection),
            patch.object(api, "_ensure_tenant"),
            patch.object(api, "_set_user_pin", return_value=["tenant-a", "tenant-b"]) as set_pin,
            patch.object(api, "_record_device_audit") as record_audit,
        ):
            response = await api.users_pin(request)

        authorize.assert_called_once()
        set_pin.assert_called_once_with(
            connection,
            "tenant-a",
            "user-a",
            "8462",
            requires_change=True,
        )
        self.assertTrue(response["requiresChange"])
        self.assertEqual(response["affectedTenantCount"], 2)
        self.assertTrue(
            any(statement.startswith("UPDATE api_sessions") for statement, _ in connection.statements)
        )
        session_update = next(
            parameters
            for statement, parameters in connection.statements
            if statement.startswith("UPDATE api_sessions")
        )
        self.assertEqual(session_update[1:3], ("tenant-a", "tenant-b"))
        self.assertEqual(record_audit.call_count, 2)


if __name__ == "__main__":
    unittest.main()
