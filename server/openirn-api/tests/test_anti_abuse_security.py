from __future__ import annotations

import io
import ipaddress
import json
import os
import sys
import unittest
import zipfile
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException


APP_DIR = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP_DIR))

import main as api  # noqa: E402


class _Request:
    def __init__(self, peer: str, headers: dict[str, str] | None = None):
        self.headers = headers or {}
        self.client = type("Client", (), {"host": peer})()


class _JsonRequest(_Request):
    def __init__(self, payload: dict[str, object], peer: str = "192.0.2.10"):
        super().__init__(peer)
        self.payload = payload

    async def json(self):
        return self.payload


class EnrollmentSecretTests(unittest.TestCase):
    def test_enrollment_operations_fail_closed_without_deployment_secret(self):
        with patch.dict(os.environ, {api.ENROLLMENT_CODE_SECRET_ENV: ""}, clear=False):
            with self.assertRaises(HTTPException) as raised:
                api._enrollment_code_hash("tenant-a", "ABCD-EFGH")

        self.assertEqual(raised.exception.status_code, 503)


class EnrollmentRequesterEmailTests(unittest.IsolatedAsyncioTestCase):
    async def test_enrollment_request_requires_a_valid_email_before_database_access(self):
        for email in ("", "invalid", "alice@example"):
            with self.subTest(email=email), patch.object(api, "_db") as database:
                request = _JsonRequest(
                    {
                        "tenantId": "tenant-a",
                        "deviceName": "Laptop Alice",
                        "platform": "linux",
                        "requesterEmail": email,
                    }
                )
                with self.assertRaises(HTTPException) as raised:
                    await api.devices_enrollment_request(request)

                self.assertEqual(raised.exception.status_code, 400)
                database.assert_not_called()

    def test_email_is_trimmed_and_normalized(self):
        self.assertEqual(
            api._normalize_email("  Alice.Security@Example.TEST  "),
            "alice.security@example.test",
        )

    async def test_valid_email_is_persisted_with_the_tenant_scoped_request(self):
        statements: list[tuple[str, tuple[object, ...]]] = []

        class Result:
            rowcount = 1

            def __init__(self, row=None):
                self.row = row

            def fetchone(self):
                return self.row

        class Connection:
            def execute(self, sql, parameters=None):
                normalized = " ".join(sql.split())
                values = tuple(parameters or ())
                statements.append((normalized, values))
                if normalized.startswith("SELECT 1 FROM tenants"):
                    return Result({"exists": 1})
                if normalized.startswith("SELECT COUNT(*) AS total"):
                    return Result({"total": 0})
                return Result()

            def commit(self):
                return None

        connection = Connection()

        @contextmanager
        def fake_db(*_args, **_kwargs):
            yield connection

        request = _JsonRequest(
            {
                "tenantId": "tenant-a",
                "deviceName": "Laptop Alice",
                "platform": "linux",
                "requesterEmail": "Alice.Security@Example.TEST",
            }
        )
        with (
            patch.object(api, "_db", fake_db),
            patch.object(api, "_resolve_tenant_id_for_request", return_value="tenant-a"),
            patch.object(api, "_expire_stale_enrollment_requests", return_value=0),
            patch.object(api, "_enforce_enrollment_rate_limit"),
            patch.object(api, "_record_device_audit"),
        ):
            result = await api.devices_enrollment_request(request)

        insertion = next(
            parameters
            for sql, parameters in statements
            if sql.startswith("INSERT INTO device_enrollment_requests")
        )
        self.assertEqual(insertion[0], "tenant-a")
        self.assertEqual(insertion[5], "alice.security@example.test")
        self.assertEqual(result["requesterEmail"], "alice.security@example.test")


class EnrollmentRequestEmailMigrationTests(unittest.TestCase):
    def test_migration_adds_requester_email_and_is_recorded(self):
        statements: list[tuple[str, tuple[object, ...]]] = []

        class Result:
            def fetchone(self):
                return None

        class Connection:
            def execute(self, sql, parameters=None):
                statements.append((" ".join(sql.split()), tuple(parameters or ())))
                return Result()

        with (
            patch.object(api, "_table_exists", return_value=True),
            patch.object(api, "_table_columns", return_value=set()),
        ):
            api._migrate_enrollment_request_email_schema(Connection())

        self.assertTrue(
            any(
                "ADD COLUMN requester_email VARCHAR(254)" in sql
                for sql, _parameters in statements
            )
        )
        self.assertTrue(
            any(
                "schema_migrations" in sql
                and parameters == (172, "enrollment_request_email")
                for sql, parameters in statements
            )
        )


class EnrollmentCodeEmailTests(unittest.IsolatedAsyncioTestCase):
    def test_smtp_delivery_uses_starttls_and_authentication(self):
        environment = {
            "OPENIRN_SMTP_HOST": "smtp.example.test",
            "OPENIRN_SMTP_PORT": "587",
            "OPENIRN_SMTP_SECURITY": "starttls",
            "OPENIRN_SMTP_FROM": "openirn@example.test",
            "OPENIRN_SMTP_USERNAME": "openirn-user",
            "OPENIRN_SMTP_PASSWORD": "smtp-secret",
            "OPENIRN_SMTP_TIMEOUT_SECONDS": "10",
        }
        with (
            patch.dict(os.environ, environment, clear=False),
            patch.object(api.ssl, "create_default_context") as create_context,
            patch.object(api.smtplib, "SMTP") as smtp_class,
        ):
            smtp = smtp_class.return_value
            api._send_enrollment_code_email(
                recipient="alice@example.test",
                code="ABCD-EFGH-JKMN-PQ",
                device_name="Laptop Alice",
                tenant_display_name="Tenant A",
                expires_at="2026-09-10T12:00:00+00:00",
            )

        smtp_class.assert_called_once_with("smtp.example.test", 587, timeout=10.0)
        smtp.starttls.assert_called_once_with(context=create_context.return_value)
        smtp.login.assert_called_once_with("openirn-user", "smtp-secret")
        message = smtp.send_message.call_args.args[0]
        self.assertEqual(message["To"], "alice@example.test")
        self.assertIn("ABCD-EFGH-JKMN-PQ", message.get_content())

    async def test_email_send_is_tenant_scoped_and_does_not_audit_code_or_email(self):
        statements: list[tuple[str, tuple[object, ...]]] = []

        class Result:
            def __init__(self, row=None):
                self.row = row

            def fetchone(self):
                return self.row

        class Connection:
            def execute(self, sql, parameters=None):
                normalized = " ".join(sql.split())
                values = tuple(parameters or ())
                statements.append((normalized, values))
                if normalized.startswith("SELECT r.status"):
                    return Result(
                        {
                            "status": "approved",
                            "requester_email": "alice@example.test",
                            "device_name": "Laptop Alice",
                            "enrollment_id": "enrollment-a",
                            "code_hash": "expected-hash",
                            "expires_at": "2999-09-10T12:00:00+00:00",
                            "consumed_at": None,
                            "revoked_at": None,
                            "tenant_display_name": "Tenant A",
                        }
                    )
                return Result()

            def commit(self):
                return None

        connection = Connection()

        @contextmanager
        def fake_db(*_args, **_kwargs):
            yield connection

        audit_payloads: list[dict[str, object]] = []

        def record_audit(_con, _tenant_id, _event_type, *, payload=None, **_kwargs):
            audit_payloads.append(dict(payload or {}))

        request = _JsonRequest(
            {
                "tenantId": "tenant-a",
                "enrollmentId": "enrollment-a",
                "code": "ABCD-EFGH-JKMN-PQ",
            }
        )
        with (
            patch.object(api, "_db", fake_db),
            patch.object(
                api,
                "_require_campaign_manager_authorization",
                return_value={"userId": "pilot-a"},
            ),
            patch.object(api, "_enrollment_code_hash", return_value="expected-hash"),
            patch.object(api, "_send_enrollment_code_email") as send_email,
            patch.object(api, "_record_device_audit", side_effect=record_audit),
        ):
            result = await api.devices_enrollment_request_send_code("request-a", request)

        self.assertEqual(result["status"], "sent")
        self.assertTrue(
            any(
                sql.startswith("SELECT r.status")
                and parameters == ("tenant-a", "request-a")
                for sql, parameters in statements
            )
        )
        send_email.assert_called_once_with(
            recipient="alice@example.test",
            code="ABCD-EFGH-JKMN-PQ",
            device_name="Laptop Alice",
            tenant_display_name="Tenant A",
            expires_at="2999-09-10T12:00:00+00:00",
        )
        self.assertNotIn("alice@example.test", str(audit_payloads))
        self.assertNotIn("ABCD-EFGH", str(audit_payloads))

    def test_enrollment_hash_is_bound_to_deployment_secret(self):
        with patch.dict(os.environ, {api.ENROLLMENT_CODE_SECRET_ENV: "a" * 32}, clear=False):
            first = api._enrollment_code_hash("tenant-a", "ABCD-EFGH")
        with patch.dict(os.environ, {api.ENROLLMENT_CODE_SECRET_ENV: "b" * 32}, clear=False):
            second = api._enrollment_code_hash("tenant-a", "ABCD-EFGH")

        self.assertNotEqual(first, second)

    def test_new_enrollment_codes_have_fourteen_characters(self):
        code = api._new_enrollment_code()
        self.assertEqual(len(code), 14)
        self.assertRegex(code, r"^[A-Z2-9]+$")


class TrustedProxyTests(unittest.TestCase):
    def test_forwarded_headers_are_ignored_from_untrusted_peer(self):
        request = _Request("203.0.113.10", {"x-forwarded-for": "198.51.100.20"})
        with patch.object(api, "TRUSTED_PROXY_NETWORKS", (ipaddress.ip_network("127.0.0.1/32"),)):
            self.assertEqual(api._request_client_ip(request), "203.0.113.10")

    def test_rightmost_untrusted_hop_is_selected_behind_trusted_proxies(self):
        request = _Request(
            "10.0.0.3",
            {"x-forwarded-for": "192.0.2.99, 198.51.100.8, 10.0.0.2"},
        )
        trusted = (ipaddress.ip_network("10.0.0.0/24"),)
        with patch.object(api, "TRUSTED_PROXY_NETWORKS", trusted):
            self.assertEqual(api._request_client_ip(request), "198.51.100.8")

    def test_invalid_trusted_proxy_configuration_is_rejected(self):
        with self.assertRaises(RuntimeError):
            api._parse_trusted_proxy_networks("127.0.0.1/32,not-a-network")


class RequestBodyLimitTests(unittest.IsolatedAsyncioTestCase):
    async def _run(self, scope, messages):
        sent: list[dict[str, object]] = []
        called = False

        async def application(inner_scope, receive, send):
            nonlocal called
            called = True
            while True:
                message = await receive()
                if not message.get("more_body"):
                    break
            await send({"type": "http.response.start", "status": 204, "headers": []})
            await send({"type": "http.response.body", "body": b""})

        queue = list(messages)

        async def receive():
            return queue.pop(0)

        async def send(message):
            sent.append(message)

        middleware = api.RequestBodyLimitMiddleware(application)
        await middleware(scope, receive, send)
        return called, sent

    async def test_content_length_is_rejected_before_endpoint(self):
        scope = {
            "type": "http",
            "method": "POST",
            "path": "/auth/verify",
            "headers": [(b"content-length", b"11")],
        }
        with patch.object(api, "MAX_REQUEST_BODY_BYTES", 10):
            called, sent = await self._run(scope, [])

        self.assertFalse(called)
        self.assertEqual(sent[0]["status"], 413)
        headers = dict(sent[0]["headers"])
        self.assertNotIn(b"connection", headers)

    async def test_streamed_body_without_content_length_is_counted(self):
        scope = {"type": "http", "method": "POST", "path": "/auth/verify", "headers": []}
        messages = [
            {"type": "http.request", "body": b"123456", "more_body": True},
            {"type": "http.request", "body": b"789012", "more_body": False},
        ]
        with patch.object(api, "MAX_REQUEST_BODY_BYTES", 10):
            called, sent = await self._run(scope, messages)

        self.assertTrue(called)
        self.assertEqual(sent[0]["status"], 413)
        payload = json.loads(sent[1]["body"].decode("utf-8"))
        self.assertIn("10", payload["detail"])

    async def test_content_length_and_transfer_encoding_are_rejected_together(self):
        scope = {
            "type": "http",
            "method": "POST",
            "path": "/auth/verify",
            "headers": [(b"content-length", b"4"), (b"transfer-encoding", b"chunked")],
        }
        called, sent = await self._run(scope, [])
        self.assertFalse(called)
        self.assertEqual(sent[0]["status"], 400)

    def test_sync_push_has_its_own_larger_limit(self):
        with (
            patch.object(api, "MAX_REQUEST_BODY_BYTES", 10),
            patch.object(api, "MAX_SYNC_PUSH_BODY_BYTES", 20),
        ):
            self.assertEqual(api._request_body_limit("/auth/verify"), 10)
            self.assertEqual(api._request_body_limit("/sync/push"), 20)

    async def test_middleware_is_effective_in_the_fastapi_stack(self):
        scope = {
            "type": "http",
            "asgi": {"version": "3.0"},
            "http_version": "1.1",
            "method": "POST",
            "scheme": "https",
            "path": "/auth/verify",
            "raw_path": b"/auth/verify",
            "query_string": b"",
            "root_path": "",
            "headers": [(b"origin", b"https://www.archoad.io")],
            "client": ("127.0.0.1", 12345),
            "server": ("testserver", 443),
        }
        messages = [
            {"type": "http.request", "body": b"123456", "more_body": True},
            {"type": "http.request", "body": b"789012", "more_body": False},
        ]
        sent: list[dict[str, object]] = []

        async def receive():
            return messages.pop(0)

        async def send(message):
            sent.append(message)

        with patch.object(api, "MAX_REQUEST_BODY_BYTES", 10):
            await api.app(scope, receive, send)

        self.assertEqual(sent[0]["status"], 413)
        headers = dict(sent[0]["headers"])
        self.assertEqual(headers[b"access-control-allow-origin"], b"https://www.archoad.io")


class ExcelArchiveLimitTests(unittest.TestCase):
    def test_large_uncompressed_xlsx_archive_is_rejected(self):
        output = io.BytesIO()
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("xl/worksheets/sheet1.xml", b"A" * 2048)

        with patch.object(api, "MAX_INVENTORY_XLSX_UNCOMPRESSED_BYTES", 1024):
            with self.assertRaises(HTTPException) as raised:
                api._validate_inventory_xlsx_archive(output.getvalue())

        self.assertEqual(raised.exception.status_code, 413)


class ExistingDeviceEnrollmentTests(unittest.TestCase):
    def test_existing_authorization_is_never_rotated_implicitly(self):
        statements: list[tuple[str, tuple[object, ...]]] = []

        class Result:
            rowcount = 1

            def fetchone(self):
                return {"exists": 1}

        class Connection:
            def execute(self, sql, parameters=None):
                statements.append((" ".join(sql.split()), tuple(parameters or ())))
                return Result()

        with self.assertRaises(HTTPException) as raised:
            api._create_device(
                Connection(),
                "tenant-a",
                name="Terminal",
                enrollment_id="enrollment-a",
                device_id="device-a",
            )

        self.assertEqual(raised.exception.status_code, 409)
        self.assertFalse(any(sql.startswith("UPDATE authorized_devices") for sql, _ in statements))
        self.assertTrue(
            any(
                sql.startswith("INSERT INTO device_audit_log")
                and "enrollment.reenrollment_blocked" in parameters
                for sql, parameters in statements
            )
        )


class ReusableEnrollmentMigrationTests(unittest.TestCase):
    def test_migration_is_additive_idempotent_and_recorded(self):
        statements: list[str] = []

        class Result:
            def fetchone(self):
                return None

        class Connection:
            def execute(self, sql, parameters=None):
                statements.append(" ".join(sql.split()))
                return Result()

        with (
            patch.object(api, "_table_exists", return_value=True),
            patch.object(api, "_table_columns", return_value={"expires_at"}),
            patch.object(api, "_migration_applied", return_value=False),
            patch.object(api, "_index_exists", return_value=False),
        ):
            api._migrate_reusable_enrollment_codes_schema(Connection())

        for column in (
            "mode",
            "max_active_devices",
            "use_count",
            "last_used_at",
            "revoked_at",
            "revoked_by_user_id",
        ):
            self.assertTrue(
                any(f"ADD COLUMN {column} " in sql for sql in statements),
                column,
            )
        self.assertTrue(
            any("MODIFY COLUMN expires_at VARCHAR(40) NULL" in sql for sql in statements)
        )
        self.assertTrue(
            any("idx_device_enrollment_codes_tenant_mode_revoked" in sql for sql in statements)
        )
        self.assertTrue(any("schema_migrations" in sql for sql in statements))


class ReusableEnrollmentAuthorizationTests(unittest.IsolatedAsyncioTestCase):
    async def test_reusable_invitation_requires_administrator_role(self):
        request = _JsonRequest(
            {
                "tenantId": "tenant-a",
                "label": "Microsoft certification",
                "mode": api.ENROLLMENT_MODE_REUSABLE,
                "maxActiveDevices": 10,
            }
        )
        with (
            patch.object(
                api,
                "_require_campaign_manager_authorization",
                return_value={"userId": "pilot-a"},
            ),
            patch.object(
                api,
                "_require_admin_authorization",
                side_effect=HTTPException(status_code=403, detail="admin required"),
            ),
        ):
            with self.assertRaises(HTTPException) as raised:
                await api.devices_enrollment(request)

        self.assertEqual(raised.exception.status_code, 403)


class ReusableEnrollmentConsumptionTests(unittest.IsolatedAsyncioTestCase):
    class Result:
        rowcount = 1

        def __init__(self, row=None, rows=None):
            self.row = row
            self.rows = rows or []

        def fetchone(self):
            return self.row

        def fetchall(self):
            return self.rows

    class Connection:
        def __init__(self, *, active_count: int = 0, revoked_at=None):
            self.active_count = active_count
            self.revoked_at = revoked_at
            self.statements: list[tuple[str, tuple[object, ...]]] = []
            self.commits = 0

        def execute(self, sql, parameters=None):
            normalized = " ".join(sql.split())
            values = tuple(parameters or ())
            self.statements.append((normalized, values))
            if normalized.startswith("SELECT 1 FROM tenants"):
                return ReusableEnrollmentConsumptionTests.Result({"exists": 1})
            if "FROM device_enrollment_codes" in normalized and "code_hash" in normalized:
                return ReusableEnrollmentConsumptionTests.Result(
                    {
                        "tenant_id": "tenant-a",
                        "enrollment_id": "enrollment-certification",
                        "created_by_user_id": "admin-a",
                        "label": "Microsoft certification",
                        "mode": api.ENROLLMENT_MODE_REUSABLE,
                        "expires_at": None,
                        "consumed_at": None,
                        "consumed_by_device_id": None,
                        "max_active_devices": 10,
                        "use_count": 2,
                        "last_used_at": None,
                        "revoked_at": self.revoked_at,
                        "created_at": "2026-09-01T00:00:00+00:00",
                    }
                )
            if normalized.startswith("SELECT COUNT(*) AS total FROM authorized_devices"):
                return ReusableEnrollmentConsumptionTests.Result(
                    {"total": self.active_count}
                )
            return ReusableEnrollmentConsumptionTests.Result()

        def commit(self):
            self.commits += 1

    async def _consume(self, connection, device_id: str):
        @contextmanager
        def fake_db(*_args, **_kwargs):
            yield connection

        request = _JsonRequest(
            {
                "tenantId": "tenant-a",
                "code": "ABCD-EFGH-JKMN-PQ",
                "deviceName": f"Certification {device_id}",
                "platform": "windows",
                "deviceId": device_id,
            }
        )
        with (
            patch.object(api, "_db", fake_db),
            patch.object(api, "_enrollment_code_hash", return_value="code-hash"),
            patch.object(api, "_enforce_enrollment_rate_limit"),
            patch.object(
                api,
                "_create_device",
                return_value=(
                    {
                        "tenantId": "tenant-a",
                        "deviceId": device_id,
                        "name": f"Certification {device_id}",
                    },
                    f"odt_{device_id}",
                ),
            ) as create_device,
        ):
            result = await api.devices_enrollment_consume(request)
        return result, create_device

    async def test_reusable_invitation_can_enroll_distinct_devices_without_consumption(self):
        for device_id in ("device-a", "device-b"):
            connection = self.Connection(active_count=1)
            result, create_device = await self._consume(connection, device_id)

            self.assertEqual(result["apiToken"], f"odt_{device_id}")
            create_device.assert_called_once()
            enrollment_select = next(
                parameters
                for sql, parameters in connection.statements
                if "FROM device_enrollment_codes" in sql and "code_hash" in sql
            )
            self.assertEqual(enrollment_select, ("tenant-a", "code-hash"))
            self.assertTrue(
                any(
                    "SET use_count = use_count + 1, last_used_at = ?" in sql
                    for sql, _ in connection.statements
                )
            )
            self.assertFalse(
                any("SET consumed_at = ?" in sql for sql, _ in connection.statements)
            )
            audit_payloads = [
                str(parameters[-1])
                for sql, parameters in connection.statements
                if sql.startswith("INSERT INTO device_audit_log")
            ]
            self.assertFalse(any("ABCD" in payload for payload in audit_payloads))

    async def test_reusable_invitation_refuses_new_device_at_capacity(self):
        connection = self.Connection(active_count=10)
        with self.assertRaises(HTTPException) as raised:
            _result, create_device = await self._consume(connection, "device-c")

        self.assertEqual(raised.exception.status_code, 409)
        self.assertGreaterEqual(connection.commits, 1)

    async def test_revoked_reusable_invitation_is_rejected(self):
        connection = self.Connection(
            active_count=0,
            revoked_at="2026-09-01T12:00:00+00:00",
        )
        with self.assertRaises(HTTPException) as raised:
            await self._consume(connection, "device-d")

        self.assertEqual(raised.exception.status_code, 410)


class ReusableEnrollmentRevocationTests(unittest.TestCase):
    def test_revocation_cascades_to_tenant_scoped_devices_and_sessions(self):
        statements: list[tuple[str, tuple[object, ...]]] = []

        class Result:
            rowcount = 1

            def __init__(self, row=None, rows=None):
                self.row = row
                self.rows = rows or []

            def fetchone(self):
                return self.row

            def fetchall(self):
                return self.rows

        class Connection:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def execute(self, sql, parameters=None):
                normalized = " ".join(sql.split())
                values = tuple(parameters or ())
                statements.append((normalized, values))
                if "SELECT enrollment_id, mode, label, revoked_at" in normalized:
                    return Result(
                        {
                            "enrollment_id": "enrollment-certification",
                            "mode": api.ENROLLMENT_MODE_REUSABLE,
                            "label": "Microsoft certification",
                            "revoked_at": None,
                        }
                    )
                if normalized.startswith("SELECT device_id, name, platform, last_seen_at"):
                    return Result(
                        rows=[
                            {
                                "device_id": "device-a",
                                "name": "Microsoft A",
                                "platform": "windows",
                                "last_seen_at": "2026-09-01T10:00:00+00:00",
                            },
                            {
                                "device_id": "device-b",
                                "name": "Microsoft B",
                                "platform": "windows",
                                "last_seen_at": "2026-09-01T11:00:00+00:00",
                            },
                        ]
                    )
                return Result()

        connection = Connection()

        @contextmanager
        def fake_db(*_args, **_kwargs):
            yield connection

        request = _Request("192.0.2.10")
        with (
            patch.object(api, "_db", fake_db),
            patch.object(
                api,
                "_resolve_tenant_id_for_request",
                return_value="tenant-a",
            ),
            patch.object(
                api,
                "_require_admin_authorization",
                return_value={"userId": "administrator-a"},
            ),
            patch.object(api, "_list_devices", return_value=[]),
            patch.object(
                api,
                "_list_reusable_enrollment_invitations",
                return_value=[],
            ),
        ):
            result = api.reusable_enrollment_revoke(
                "enrollment-certification",
                request,
                tenantId="tenant-a",
                revokeDevices=True,
            )

        self.assertEqual(result["revokedDeviceIds"], ["device-a", "device-b"])
        session_updates = [
            parameters
            for sql, parameters in statements
            if sql.startswith("UPDATE api_sessions SET revoked_at")
        ]
        self.assertEqual(
            [parameters[2] for parameters in session_updates],
            ["device-a", "device-b"],
        )
        self.assertTrue(
            any(
                sql.startswith("DELETE FROM authorized_devices")
                and parameters == ("tenant-a", "enrollment-certification")
                for sql, parameters in statements
            )
        )
        self.assertTrue(
            all(
                parameters[1] == "tenant-a"
                for parameters in session_updates
            )
        )


class RateLimitSqlTests(unittest.TestCase):
    def test_atomic_bucket_upsert_is_translated_for_mariadb(self):
        translated = api._translate_mysql_sql(
            """
            INSERT INTO api_rate_limit_buckets(tenant_id, scope, subject_hash, window_started_at, request_count, updated_at)
            VALUES (?, ?, ?, ?, 1, ?)
            ON CONFLICT(tenant_id, scope, subject_hash, window_started_at)
            DO UPDATE SET request_count = request_count + 1, updated_at = excluded.updated_at
            """
        )
        self.assertIn("ON DUPLICATE KEY UPDATE", translated)
        self.assertIn("updated_at = VALUES(updated_at)", translated)

    def test_limit_excess_is_committed_and_returns_retry_after(self):
        class Result:
            rowcount = 1

            def __init__(self, row=None):
                self.row = row

            def fetchone(self):
                return self.row

        class Connection:
            def __init__(self):
                self.commits = 0

            def execute(self, sql, parameters=None):
                if "SELECT request_count" in sql:
                    return Result({"request_count": 2})
                return Result()

            def commit(self):
                self.commits += 1

        connection = Connection()
        with self.assertRaises(HTTPException) as raised:
            api._enforce_enrollment_rate_limit(
                connection,
                "tenant-a",
                operation="request",
                ip_address="192.0.2.1",
                max_by_ip=1,
                max_by_tenant=10,
            )

        self.assertEqual(raised.exception.status_code, 429)
        self.assertGreater(int(raised.exception.headers["Retry-After"]), 0)
        self.assertEqual(connection.commits, 1)


if __name__ == "__main__":
    unittest.main()
