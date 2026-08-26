from __future__ import annotations

import hashlib
import sys
import unittest
from pathlib import Path
from unittest.mock import patch


TOOLS_DIR = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS_DIR))

import reset_poc_access as reset  # noqa: E402


class _Connection:
    def __init__(self) -> None:
        self.committed = False

    def commit(self) -> None:
        self.committed = True


class ResetPocAccessTests(unittest.TestCase):
    def test_apply_requires_backup_and_exact_confirmation(self) -> None:
        with self.assertRaises(ValueError):
            reset.validate_apply_request(
                apply=True,
                backup_confirmed=False,
                confirmation=reset.CONFIRMATION_TEXT,
            )
        with self.assertRaises(ValueError):
            reset.validate_apply_request(
                apply=True,
                backup_confirmed=True,
                confirmation="incorrect",
            )
        reset.validate_apply_request(
            apply=True,
            backup_confirmed=True,
            confirmation=reset.CONFIRMATION_TEXT,
        )

    def test_schema_requires_pin_and_enrollment_security_migrations(self) -> None:
        tables = [{"table_name": table} for table in reset.REQUIRED_TABLES]
        with patch.object(
            reset,
            "fetchall",
            side_effect=[tables, [{"version": 169}]],
        ):
            with self.assertRaisesRegex(RuntimeError, "170"):
                reset.verify_schema(object())

        with patch.object(
            reset,
            "fetchall",
            side_effect=[tables, [{"version": 169}, {"version": 170}]],
        ):
            reset.verify_schema(object())

    def test_pin_hash_matches_api_pbkdf2_format(self) -> None:
        salt = "00112233445566778899aabbccddeeff"
        expected = hashlib.pbkdf2_hmac(
            "sha256",
            b"0000",
            salt.encode("utf-8"),
            200_000,
        ).hex()

        self.assertEqual(reset.pin_hash("0000", salt, 200_000), expected)
        self.assertNotIn("0000", expected)

    def test_reset_revokes_access_and_marks_every_pin_temporary(self) -> None:
        connection = _Connection()
        users = [
            {"tenant_id": "tenant-a", "user_id": "user-a"},
            {"tenant_id": "tenant-b", "user_id": "user-b"},
        ]
        before = {
            "tenants": 1,
            "users": 1,
            "credentials": 1,
            "authorizedDevices": 1,
            "activeSessions": 1,
            "openEnrollmentRequests": 1,
            "unusedEnrollmentCodes": 1,
        }

        with (
            patch.object(reset, "collect_counts", return_value=before),
            patch.object(reset, "fetchall", return_value=users),
            patch.object(reset, "execute", return_value=1) as execute,
        ):
            changed = reset.reset_access(
                connection,
                ["tenant-a", "tenant-b"],
                iterations=200_000,
                salt_factory=iter(["salt-a", "salt-b"]).__next__,
            )

        self.assertTrue(connection.committed)
        self.assertEqual(changed["credentialsReset"], 2)
        statements = [" ".join(call.args[1].split()) for call in execute.call_args_list]
        self.assertTrue(any(sql.startswith("UPDATE api_sessions") for sql in statements))
        self.assertTrue(any(sql.startswith("DELETE FROM authorized_devices") for sql in statements))
        self.assertTrue(any("requires_change" in sql for sql in statements))
        credential_calls = [
            call
            for call in execute.call_args_list
            if "INSERT INTO user_credentials" in call.args[1]
        ]
        self.assertEqual(len(credential_calls), 2)
        self.assertNotEqual(credential_calls[0].args[2][4], credential_calls[1].args[2][4])
        self.assertNotIn("0000", credential_calls[0].args[2])


if __name__ == "__main__":
    unittest.main()
