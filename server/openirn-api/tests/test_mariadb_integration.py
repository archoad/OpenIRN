from __future__ import annotations

import os
import sys
import unittest
import uuid
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse
from unittest.mock import patch

from fastapi import HTTPException


APP_DIR = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP_DIR))

import main as api  # noqa: E402
from database_contract import REQUIRED_MIGRATIONS, REQUIRED_TABLES  # noqa: E402


TEST_MYSQL_URL = os.environ.get("OPENIRN_TEST_MYSQL_URL", "").strip()


def _config(raw_url: str) -> dict[str, object]:
    parsed = urlparse(raw_url)
    query = parse_qs(parsed.query)
    return {
        "host": parsed.hostname or "127.0.0.1",
        "port": int(parsed.port or 3306),
        "user": unquote(parsed.username or ""),
        "password": unquote(parsed.password or ""),
        "database": parsed.path.lstrip("/"),
        "charset": (query.get("charset") or ["utf8mb4"])[0],
    }


@unittest.skipUnless(TEST_MYSQL_URL, "OPENIRN_TEST_MYSQL_URL absent")
class MariaDbIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import pymysql  # type: ignore

        cls.pymysql = pymysql
        cls.config = _config(TEST_MYSQL_URL)

    def connect(self, *, autocommit: bool = False):
        return self.pymysql.connect(**self.config, autocommit=autocommit)

    def test_schema_and_required_migrations_are_present(self):
        with self.connect() as con:
            with con.cursor() as cur:
                cur.execute(
                    """
                    SELECT table_name
                    FROM information_schema.tables
                    WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE'
                    """
                )
                tables = {str(row[0]) for row in cur.fetchall()}
                cur.execute("SELECT version, name FROM schema_migrations")
                migrations = {int(version): str(name) for version, name in cur.fetchall()}

        self.assertFalse(set(REQUIRED_TABLES) - tables)
        self.assertFalse(set(REQUIRED_MIGRATIONS) - set(migrations))

    def test_runtime_account_has_dml_but_no_ddl(self):
        status = api._verify_runtime_schema()
        privileges = set(status["privileges"])
        self.assertTrue({"DELETE", "INSERT", "SELECT", "UPDATE"}.issubset(privileges))
        self.assertFalse({"ALTER", "CREATE", "DROP", "INDEX"} & privileges)

        tenant_id = str(uuid.uuid4())
        with self.connect() as con:
            with con.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO tenants(id, display_name, description, permanent, created_at, updated_at)
                    VALUES (%s, %s, '', 0, 'ci', 'ci')
                    """,
                    (tenant_id, "CI runtime DML"),
                )
                cur.execute("SELECT display_name FROM tenants WHERE id = %s", (tenant_id,))
                self.assertEqual(cur.fetchone()[0], "CI runtime DML")
            con.rollback()

        with self.connect(autocommit=True) as con:
            with con.cursor() as cur:
                with self.assertRaises(self.pymysql.MySQLError):
                    cur.execute("CREATE TABLE openirn_runtime_must_not_create_tables(id INT)")


@unittest.skipUnless(TEST_MYSQL_URL, "OPENIRN_TEST_MYSQL_URL absent")
class ReusableEnrollmentMariaDbIntegrationTests(unittest.IsolatedAsyncioTestCase):
    @classmethod
    def setUpClass(cls):
        import pymysql  # type: ignore

        cls.pymysql = pymysql
        cls.config = _config(TEST_MYSQL_URL)

    def connect(self, *, autocommit: bool = False):
        return self.pymysql.connect(
            **self.config,
            autocommit=autocommit,
            cursorclass=self.pymysql.cursors.DictCursor,
        )

    async def test_reusable_invitation_full_lifecycle_is_tenant_scoped(self):
        tenant_id = str(uuid.uuid4())
        other_tenant_id = str(uuid.uuid4())
        device_ids = [f"device-{uuid.uuid4()}", f"device-{uuid.uuid4()}"]
        now = "2026-09-01T00:00:00+00:00"

        class Request:
            def __init__(self, payload=None):
                self.payload = payload or {}
                self.headers = {}
                self.client = type("Client", (), {"host": "192.0.2.10"})()

            async def json(self):
                return self.payload

        with self.connect() as con:
            with con.cursor() as cur:
                for current_tenant_id in (tenant_id, other_tenant_id):
                    cur.execute(
                        """
                        INSERT INTO tenants(
                            id, display_name, description, permanent, created_at, updated_at
                        ) VALUES (%s, %s, '', 0, %s, %s)
                        """,
                        (current_tenant_id, "Certification integration", now, now),
                    )
            con.commit()

        try:
            creation_request = Request(
                {
                    "tenantId": tenant_id,
                    "label": "Microsoft certification",
                    "mode": api.ENROLLMENT_MODE_REUSABLE,
                    "maxActiveDevices": 10,
                }
            )
            with (
                patch.object(
                    api,
                    "_require_campaign_manager_authorization",
                    return_value={"userId": "administrator-integration"},
                ),
                patch.object(
                    api,
                    "_require_admin_authorization",
                    return_value={"userId": "administrator-integration"},
                ),
                patch.dict(
                    os.environ,
                    {api.ENROLLMENT_CODE_SECRET_ENV: "integration-test-pepper-32-characters-minimum"},
                    clear=False,
                ),
            ):
                invitation = await api.devices_enrollment(creation_request)

            self.assertTrue(invitation["reusable"])
            self.assertIsNone(invitation["expiresAt"])
            self.assertEqual(invitation["maxActiveDevices"], 10)
            code = str(invitation["code"])
            enrollment_id = str(invitation["enrollmentId"])

            tokens: list[str] = []
            for device_id in device_ids:
                consume_request = Request(
                    {
                        "tenantId": tenant_id,
                        "code": code,
                        "deviceName": f"Microsoft {device_id}",
                        "platform": "windows",
                        "deviceId": device_id,
                    }
                )
                with patch.dict(
                    os.environ,
                    {api.ENROLLMENT_CODE_SECRET_ENV: "integration-test-pepper-32-characters-minimum"},
                    clear=False,
                ):
                    consumed = await api.devices_enrollment_consume(consume_request)
                tokens.append(str(consumed["apiToken"]))

            self.assertEqual(len(set(tokens)), 2)
            for token in tokens:
                self.assertEqual(
                    api._device_token_auth_context(token)["tenantId"],
                    tenant_id,
                )

            wrong_tenant_request = Request(
                {
                    "tenantId": other_tenant_id,
                    "code": code,
                    "deviceName": "Wrong tenant",
                    "platform": "windows",
                    "deviceId": f"device-{uuid.uuid4()}",
                }
            )
            with (
                patch.dict(
                    os.environ,
                    {api.ENROLLMENT_CODE_SECRET_ENV: "integration-test-pepper-32-characters-minimum"},
                    clear=False,
                ),
                self.assertRaises(HTTPException) as raised,
            ):
                await api.devices_enrollment_consume(wrong_tenant_request)
            self.assertEqual(raised.exception.status_code, 404)

            with self.connect() as con:
                with con.cursor() as cur:
                    cur.execute(
                        """
                        SELECT consumed_at, use_count, max_active_devices, revoked_at
                        FROM device_enrollment_codes
                        WHERE tenant_id = %s AND enrollment_id = %s
                        """,
                        (tenant_id, enrollment_id),
                    )
                    row = cur.fetchone()
                    self.assertIsNone(row["consumed_at"])
                    self.assertEqual(int(row["use_count"]), 2)
                    self.assertEqual(int(row["max_active_devices"]), 10)
                    self.assertIsNone(row["revoked_at"])
                    cur.execute(
                        """
                        SELECT COUNT(*) AS total
                        FROM device_audit_log
                        WHERE tenant_id = %s AND payload_json LIKE %s
                        """,
                        (tenant_id, f"%{code}%"),
                    )
                    self.assertEqual(int(cur.fetchone()["total"]), 0)

            with patch.object(
                api,
                "_require_admin_authorization",
                return_value={"userId": "administrator-integration"},
            ):
                revoked = api.reusable_enrollment_revoke(
                    enrollment_id,
                    Request(),
                    tenantId=tenant_id,
                    revokeDevices=True,
                )
            self.assertEqual(set(revoked["revokedDeviceIds"]), set(device_ids))
            for token in tokens:
                self.assertIsNone(api._device_token_auth_context(token))

            with self.connect() as con:
                with con.cursor() as cur:
                    cur.execute(
                        """
                        SELECT COUNT(*) AS total
                        FROM authorized_devices
                        WHERE tenant_id = %s AND enrollment_id = %s
                        """,
                        (tenant_id, enrollment_id),
                    )
                    self.assertEqual(int(cur.fetchone()["total"]), 0)
                    cur.execute(
                        """
                        SELECT revoked_at
                        FROM device_enrollment_codes
                        WHERE tenant_id = %s AND enrollment_id = %s
                        """,
                        (tenant_id, enrollment_id),
                    )
                    self.assertIsNotNone(cur.fetchone()["revoked_at"])
        finally:
            with self.connect() as con:
                with con.cursor() as cur:
                    cur.execute(
                        "DELETE FROM tenants WHERE id IN (%s, %s)",
                        (tenant_id, other_tenant_id),
                    )
                    cur.execute(
                        "DELETE FROM terminals WHERE device_id IN (%s, %s)",
                        tuple(device_ids),
                    )
                con.commit()


if __name__ == "__main__":
    unittest.main()
