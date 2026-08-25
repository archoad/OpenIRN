from __future__ import annotations

import os
import sys
import unittest
import uuid
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse


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


if __name__ == "__main__":
    unittest.main()
