#!/usr/bin/env python3
"""Create the first OpenIRN solution administrator in MariaDB."""

from __future__ import annotations

import argparse
import getpass
import hashlib
import json
import os
import re
import secrets
import sys
import uuid
from datetime import datetime, timezone
from typing import Any
from urllib.parse import parse_qs, unquote, urlparse


PIN_ITERATIONS = int(os.environ.get("OPENIRN_PIN_ITERATIONS", "200000"))
TENANT_RE = re.compile(r"[^a-zA-Z0-9_.-]+")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def normalize_tenant(value: str) -> str:
    normalized = TENANT_RE.sub("_", str(value or "").strip())[:80]
    if not normalized:
        raise ValueError("L’identifiant de l’espace d’administration est vide")
    return normalized


def validate_pin(pin: str) -> str:
    cleaned = str(pin or "").strip()
    if len(cleaned) < 4 or len(cleaned) > 32:
        raise ValueError("Le PIN temporaire doit contenir entre 4 et 32 caractères")
    lowered = cleaned.lower()
    weak_values = {
        str(os.environ.get("OPENIRN_DEFAULT_USER_PIN", "0000")).strip().lower(),
        "0000",
        "1111",
        "1234",
        "4321",
        "0123",
        "2580",
        "password",
        "motdepasse",
    }
    repeated = len(set(cleaned)) == 1
    sequential = cleaned.isdigit() and (
        cleaned in "01234567890123456789"
        or cleaned in "98765432109876543210"
    )
    if lowered in weak_values or repeated or sequential:
        raise ValueError("Le PIN temporaire est trop prévisible")
    return cleaned


def parse_mysql_url(raw: str) -> dict[str, Any]:
    parsed = urlparse(str(raw or "").strip())
    if parsed.scheme not in {"mysql", "mysql+pymysql", "mariadb", "mariadb+pymysql"}:
        raise ValueError("OPENIRN_API_MYSQL_URL doit utiliser mysql+pymysql:// ou mariadb+pymysql://")
    database = parsed.path.lstrip("/")
    if not parsed.username or not database:
        raise ValueError("OPENIRN_API_MYSQL_URL doit contenir un utilisateur et une base")
    query = parse_qs(parsed.query)
    return {
        "host": parsed.hostname or "127.0.0.1",
        "port": int(parsed.port or 3306),
        "user": unquote(parsed.username),
        "password": unquote(parsed.password or ""),
        "database": database,
        "charset": (query.get("charset") or ["utf8mb4"])[0] or "utf8mb4",
    }


def pin_hash(pin: str, salt: str, iterations: int = PIN_ITERATIONS) -> str:
    return hashlib.pbkdf2_hmac(
        "sha256",
        pin.encode("utf-8"),
        salt.encode("utf-8"),
        iterations,
    ).hex()


def create_superuser(
    connection: Any,
    *,
    tenant_id: str,
    tenant_display_name: str,
    user_id: str,
    first_name: str,
    last_name: str,
    email: str,
    pin: str,
) -> None:
    now = utc_now()
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT COUNT(*) AS total FROM users WHERE tenant_id = %s AND active = 1 AND role = 'administrator'",
            (tenant_id,),
        )
        row = cursor.fetchone() or {}
        if int(row.get("total") or 0) > 0:
            raise RuntimeError(
                "Un administrateur actif existe déjà dans cet espace. "
                "Utilisez l’application pour gérer les comptes."
            )

        cursor.execute("SELECT 1 FROM users WHERE user_id = %s LIMIT 1", (user_id,))
        if cursor.fetchone() is not None:
            raise RuntimeError("Cet identifiant utilisateur existe déjà")

        cursor.execute("SELECT 1 FROM tenants WHERE id = %s", (tenant_id,))
        if cursor.fetchone() is None:
            cursor.execute(
                """
                INSERT INTO tenants(id, created_at, updated_at, display_name, description, permanent)
                VALUES (%s, %s, %s, %s, %s, 0)
                """,
                (tenant_id, now, now, tenant_display_name, "Espace d’administration OpenIRN"),
            )

        user = {
            "id": user_id,
            "firstName": first_name,
            "lastName": last_name,
            "email": email,
            "role": "administrator",
            "active": True,
            "createdAt": now,
            "updatedAt": now,
        }
        cursor.execute(
            """
            INSERT INTO users(
                tenant_id, user_id, first_name, last_name, email, role,
                active, created_at, updated_at, payload_json
            ) VALUES (%s, %s, %s, %s, %s, 'administrator', 1, %s, %s, %s)
            """,
            (
                tenant_id,
                user_id,
                first_name,
                last_name,
                email,
                now,
                now,
                canonical_json(user),
            ),
        )
        salt = secrets.token_hex(16)
        cursor.execute(
            """
            INSERT INTO user_credentials(
                tenant_id, user_id, algorithm, iterations, salt, pin_hash,
                requires_change, updated_at
            ) VALUES (%s, %s, 'pbkdf2_sha256', %s, %s, %s, 1, %s)
            """,
            (tenant_id, user_id, PIN_ITERATIONS, salt, pin_hash(pin, salt), now),
        )
        cursor.execute(
            """
            INSERT INTO device_audit_log(tenant_id, device_id, event_type, created_at, payload_json)
            VALUES (%s, NULL, 'user.bootstrap_administrator_created', %s, %s)
            """,
            (
                tenant_id,
                now,
                canonical_json({"userId": user_id, "source": "server-cli", "requiresChange": True}),
            ),
        )
    connection.commit()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Créer le premier administrateur solution OpenIRN.",
    )
    parser.add_argument(
        "--tenant",
        default=os.environ.get("OPENIRN_SOLUTION_ADMIN_TENANT_ID", "archoad"),
        help="Identifiant de l’espace d’administration solution.",
    )
    parser.add_argument("--tenant-name", default="Administration OpenIRN")
    parser.add_argument("--email", required=True)
    parser.add_argument("--first-name", default="")
    parser.add_argument("--last-name", default="")
    parser.add_argument("--user-id", default="", help="UUID facultatif; un UUID est généré par défaut.")
    args = parser.parse_args()

    mysql_url = os.environ.get("OPENIRN_API_MYSQL_URL", "").strip()
    try:
        config = parse_mysql_url(mysql_url)
        tenant_id = normalize_tenant(args.tenant)
        email = str(args.email or "").strip().lower()
        if not email or "@" not in email:
            raise ValueError("Une adresse électronique valide est requise")
        raw_user_id = str(args.user_id or "").strip().lower() or str(uuid.uuid4())
        user_id = str(uuid.UUID(raw_user_id))
        pin = validate_pin(getpass.getpass("PIN temporaire (non trivial) : "))
        confirmation = getpass.getpass("Confirmer le PIN temporaire : ")
        if not secrets.compare_digest(pin, confirmation):
            raise ValueError("Les deux PIN ne correspondent pas")
    except (ValueError, TypeError) as exc:
        print(f"[ERREUR] {exc}", file=sys.stderr)
        return 2

    try:
        import pymysql  # type: ignore
        from pymysql.cursors import DictCursor  # type: ignore
    except ImportError:
        print("[ERREUR] PyMySQL est absent du venv serveur", file=sys.stderr)
        return 1

    connection = None
    try:
        connection = pymysql.connect(**config, autocommit=False, cursorclass=DictCursor)
        create_superuser(
            connection,
            tenant_id=tenant_id,
            tenant_display_name=str(args.tenant_name or tenant_id).strip()[:255],
            user_id=user_id,
            first_name=str(args.first_name or "").strip()[:255],
            last_name=str(args.last_name or "").strip()[:255],
            email=email[:255],
            pin=pin,
        )
    except Exception as exc:
        if connection is not None:
            connection.rollback()
        print(f"[ERREUR] Création refusée: {exc}", file=sys.stderr)
        return 1
    finally:
        if connection is not None:
            connection.close()

    print("Administrateur solution créé.")
    print(f"Espace : {tenant_id}")
    print(f"Compte : {email}")
    print(f"UUID   : {user_id}")
    print("Le PIN devra être remplacé lors de la première connexion.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
