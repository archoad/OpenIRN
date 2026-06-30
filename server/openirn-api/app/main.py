from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import uuid
import urllib.error
import urllib.parse
import urllib.request
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from io import BytesIO
from typing import Any, Iterator

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

APP_VERSION = "0.10.0"
DATA_DIR = Path(os.environ.get("OPENIRN_API_DATA_DIR", "/var/lib/openirn-api"))
DB_PATH = Path(os.environ.get("OPENIRN_API_DB", str(DATA_DIR / "openirn.sqlite3")))
BACKUP_DIR = Path(os.environ.get("OPENIRN_API_BACKUP_DIR", str(DATA_DIR / "backups")))
BACKUP_KEEP = int(os.environ.get("OPENIRN_API_BACKUP_KEEP", "30"))
SCHEMA_PATH = Path(os.environ.get("OPENIRN_API_SCHEMA", str(Path(__file__).resolve().parents[1] / "sql" / "schema.sql")))
TENANT_RE = re.compile(r"[^a-zA-Z0-9_.-]+")
PIN_DEFAULT = os.environ.get("OPENIRN_DEFAULT_USER_PIN", "0000")
PIN_ITERATIONS = int(os.environ.get("OPENIRN_PIN_ITERATIONS", "200000"))
OFFICIAL_ADRI_GITLAB_API = os.environ.get("OPENIRN_ADRI_GITLAB_API", "https://gitlab.com/api/v4").rstrip("/")
OFFICIAL_ADRI_PROJECT_PATH = os.environ.get("OPENIRN_ADRI_PROJECT_PATH", "digitalresilienceinitiative/adri-irn")
OFFICIAL_ADRI_TREE_PATH = os.environ.get("OPENIRN_ADRI_TREE_PATH", "Référentiel d'évaluation IRN (FR)")
OFFICIAL_ADRI_DEFAULT_BRANCH = os.environ.get("OPENIRN_ADRI_DEFAULT_BRANCH", "main")
OFFICIAL_ADRI_SOURCE_URL = os.environ.get("OPENIRN_ADRI_SOURCE_URL", "https://gitlab.com/digitalresilienceinitiative/adri-irn")
OFFICIAL_ADRI_LICENSE = os.environ.get("OPENIRN_ADRI_LICENSE", "CC BY-NC-ND 4.0")
OFFICIAL_REFERENTIAL_DIR = Path(os.environ.get("OPENIRN_REFERENTIAL_DIR", str(DATA_DIR / "referentials")))
AUTH_ATTEMPT_WINDOW_MINUTES = int(os.environ.get("OPENIRN_AUTH_ATTEMPT_WINDOW_MINUTES", "15"))
AUTH_MAX_FAILED_BY_DEVICE = int(os.environ.get("OPENIRN_AUTH_MAX_FAILED_BY_DEVICE", "5"))
AUTH_MAX_FAILED_BY_USER = int(os.environ.get("OPENIRN_AUTH_MAX_FAILED_BY_USER", "5"))
AUTH_MAX_FAILED_BY_IP = int(os.environ.get("OPENIRN_AUTH_MAX_FAILED_BY_IP", "20"))
AUTH_ATTEMPT_RETENTION_DAYS = int(os.environ.get("OPENIRN_AUTH_ATTEMPT_RETENTION_DAYS", "30"))


app = FastAPI(
    title="OpenIRN API",
    version=APP_VERSION,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://www.archoad.io",
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept"],
)


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _safe_segment(value: Any, fallback: str) -> str:
    raw = str(value or "").strip()
    if not raw:
        return fallback
    cleaned = TENANT_RE.sub("_", raw)
    return cleaned[:80] or fallback


def _canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _pretty_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2)


def _json_sha256(value: Any) -> str:
    return hashlib.sha256(_canonical_json(value).encode("utf-8")).hexdigest()


def _parse_json(raw: str | None, fallback: Any) -> Any:
    if not raw:
        return fallback
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return fallback


def _parse_datetime(value: Any) -> datetime:
    raw = str(value or "").strip()
    if not raw:
        return datetime.fromtimestamp(0, timezone.utc)
    try:
        normalized = raw.replace("Z", "+00:00")
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is None:
            return parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except ValueError:
        return datetime.fromtimestamp(0, timezone.utc)


def _configured_api_token() -> str:
    return os.environ.get("OPENIRN_API_TOKEN", "").strip()


def _extract_bearer_token(request: Request) -> str:
    authorization = request.headers.get("authorization", "").strip()
    if not authorization:
        return ""
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        return ""
    return token.strip()


def _secret_hash(value: str) -> str:
    return hashlib.sha256(str(value or "").encode("utf-8")).hexdigest()


def _enrollment_code_hash_with_pepper(tenant_id: str, code: str, pepper: str) -> str:
    normalized = _normalize_enrollment_code(code)
    return hmac.new(
        pepper.encode("utf-8"),
        f"{tenant_id}:{normalized}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def _enrollment_code_hash(tenant_id: str, code: str) -> str:
    pepper = _configured_api_token() or "openirn-device-enrollment"
    return _enrollment_code_hash_with_pepper(tenant_id, code, pepper)


def _bootstrap_enrollment_code_hash(tenant_id: str, code: str) -> str:
    return _enrollment_code_hash_with_pepper(
        tenant_id,
        code,
        "openirn-device-enrollment-bootstrap-v1",
    )


def _enrollment_code_hash_candidates(tenant_id: str, code: str) -> list[str]:
    hashes = [
        _enrollment_code_hash(tenant_id, code),
        _bootstrap_enrollment_code_hash(tenant_id, code),
    ]
    fallback_hash = _enrollment_code_hash_with_pepper(tenant_id, code, "openirn-device-enrollment")
    hashes.append(fallback_hash)
    return list(dict.fromkeys(hashes))


def _normalize_enrollment_code(value: Any) -> str:
    return re.sub(r"[^A-Z0-9]", "", str(value or "").upper())


def _format_enrollment_code(value: str) -> str:
    normalized = _normalize_enrollment_code(value)
    return "-".join(normalized[index : index + 4] for index in range(0, len(normalized), 4))


def _new_enrollment_code() -> str:
    # Crockford-like alphabet without easily confused characters. 10 chars ≈ 50 bits.
    alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    return "".join(secrets.choice(alphabet) for _ in range(10))


def _new_device_token() -> str:
    return "odt_" + secrets.token_urlsafe(36)


def _new_session_token() -> str:
    return "ost_" + secrets.token_urlsafe(36)


def _is_active_session_token(provided_token: str) -> bool:
    token_hash = _secret_hash(provided_token)
    now = _utc_now()
    try:
        with _db() as con:
            row = con.execute(
                """
                SELECT tenant_id, session_id, device_id, expires_at, revoked_at
                FROM api_sessions
                WHERE token_hash = ? AND revoked_at IS NULL
                """,
                (token_hash,),
            ).fetchone()
            if row is None:
                return False
            if _parse_datetime(row["expires_at"]) < now:
                return False
            device = con.execute(
                """
                SELECT 1
                FROM authorized_devices
                WHERE tenant_id = ? AND device_id = ?
                  AND status = 'active' AND revoked_at IS NULL
                """,
                (row["tenant_id"], row["device_id"]),
            ).fetchone()
            if device is None:
                return False
            con.execute(
                """
                UPDATE api_sessions
                SET last_seen_at = ?
                WHERE tenant_id = ? AND session_id = ?
                """,
                (now.isoformat(), row["tenant_id"], row["session_id"]),
            )
            con.execute(
                """
                UPDATE authorized_devices
                SET last_seen_at = ?
                WHERE tenant_id = ? AND device_id = ?
                """,
                (now.isoformat(), row["tenant_id"], row["device_id"]),
            )
            con.commit()
            return True
    except sqlite3.Error:
        return False


def _request_has_api_authorization(request: Request) -> bool:
    provided_token = _extract_bearer_token(request)
    if not provided_token:
        return False

    expected_token = _configured_api_token()
    if expected_token and hmac.compare_digest(provided_token, expected_token):
        return True

    if _is_active_session_token(provided_token):
        return True

    if _is_active_device_token(provided_token):
        return True

    return False


def _request_device_id(request: Request, payload: dict[str, Any] | None = None) -> str:
    header_value = request.headers.get("x-openirn-device-id", "").strip()
    if header_value:
        return header_value[:160]
    if payload:
        body_value = str(payload.get("deviceId") or "").strip()
        if body_value:
            return body_value[:160]
    return ""


def _request_client_ip(request: Request) -> str:
    forwarded_for = request.headers.get("x-forwarded-for", "").strip()
    if forwarded_for:
        return forwarded_for.split(",", 1)[0].strip()[:80]
    real_ip = request.headers.get("x-real-ip", "").strip()
    if real_ip:
        return real_ip[:80]
    if request.client and request.client.host:
        return request.client.host[:80]
    return "unknown"


def _record_auth_attempt(
    con: sqlite3.Connection,
    tenant_id: str,
    *,
    device_id: str,
    user_id: str,
    ip_address: str,
    successful: bool,
    reason: str,
) -> None:
    now = _utc_now()
    retention_start = now - timedelta(days=max(1, AUTH_ATTEMPT_RETENTION_DAYS))
    con.execute(
        """
        DELETE FROM auth_attempts
        WHERE tenant_id = ? AND created_at < ?
        """,
        (tenant_id, retention_start.isoformat()),
    )
    con.execute(
        """
        INSERT INTO auth_attempts(
            tenant_id, attempt_id, device_id, user_id, ip_address,
            successful, reason, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            tenant_id,
            "auth-" + secrets.token_urlsafe(18),
            device_id[:160],
            user_id[:160],
            ip_address[:80],
            1 if successful else 0,
            reason[:120],
            now.isoformat(),
        ),
    )


def _recent_auth_failures(
    con: sqlite3.Connection,
    tenant_id: str,
    column: str,
    value: str,
) -> int:
    allowed_columns = {"device_id", "user_id", "ip_address"}
    if column not in allowed_columns or not value:
        return 0
    window_start = (_utc_now() - timedelta(minutes=max(1, AUTH_ATTEMPT_WINDOW_MINUTES))).isoformat()
    row = con.execute(
        f"""
        SELECT COUNT(*) AS total
        FROM auth_attempts
        WHERE tenant_id = ?
          AND successful = 0
          AND created_at >= ?
          AND {column} = ?
        """,
        (tenant_id, window_start, value),
    ).fetchone()
    return int(row["total"] if row is not None else 0)


def _enforce_auth_rate_limit(
    con: sqlite3.Connection,
    tenant_id: str,
    *,
    device_id: str,
    user_id: str,
    ip_address: str,
) -> None:
    checks = [
        ("device_id", device_id, AUTH_MAX_FAILED_BY_DEVICE, "Trop de codes invalides pour ce terminal"),
        ("user_id", user_id, AUTH_MAX_FAILED_BY_USER, "Trop de codes invalides pour ce profil"),
        ("ip_address", ip_address, AUTH_MAX_FAILED_BY_IP, "Trop de tentatives depuis cette adresse réseau"),
    ]
    for column, value, limit, message in checks:
        if limit <= 0:
            continue
        if _recent_auth_failures(con, tenant_id, column, value) >= limit:
            _record_auth_attempt(
                con,
                tenant_id,
                device_id=device_id,
                user_id=user_id,
                ip_address=ip_address,
                successful=False,
                reason=f"rate_limited:{column}",
            )
            _record_device_audit(
                con,
                tenant_id,
                "auth.rate_limited",
                device_id=device_id,
                payload={
                    "userId": user_id,
                    "ipAddress": ip_address,
                    "scope": column,
                    "windowMinutes": AUTH_ATTEMPT_WINDOW_MINUTES,
                    "limit": limit,
                },
            )
            con.commit()
            raise HTTPException(
                status_code=429,
                detail=f"{message}. Réessayez dans quelques minutes.",
            )


def _require_active_device(
    request: Request,
    tenant_id: str,
    payload: dict[str, Any] | None = None,
) -> str:
    device_id = _request_device_id(request, payload)
    if not device_id:
        raise HTTPException(status_code=401, detail="Missing OpenIRN device id")
    now = _utc_now().isoformat()
    with _db() as con:
        row = con.execute(
            """
            SELECT 1
            FROM authorized_devices
            WHERE tenant_id = ? AND device_id = ?
              AND status = 'active' AND revoked_at IS NULL
            """,
            (tenant_id, device_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=403, detail="Terminal non autorisé ou révoqué")
        con.execute(
            """
            UPDATE authorized_devices
            SET last_seen_at = ?
            WHERE tenant_id = ? AND device_id = ?
            """,
            (now, tenant_id, device_id),
        )
        con.commit()
    return device_id


def _create_api_session(
    con: sqlite3.Connection,
    tenant_id: str,
    device_id: str,
    user_id: str,
    ttl_hours: int = 8,
) -> tuple[str, str, datetime]:
    token = _new_session_token()
    session_id = "session-" + secrets.token_urlsafe(18)
    now = _utc_now()
    expires_at = now + timedelta(hours=ttl_hours)
    con.execute(
        """
        INSERT INTO api_sessions(
            tenant_id, session_id, token_hash, device_id, user_id,
            created_at, expires_at, last_seen_at, revoked_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL)
        """,
        (
            tenant_id,
            session_id,
            _secret_hash(token),
            device_id,
            user_id,
            now.isoformat(),
            expires_at.isoformat(),
            now.isoformat(),
        ),
    )
    return session_id, token, expires_at


def _is_active_device_token(provided_token: str) -> bool:
    token_hash = _secret_hash(provided_token)
    now = _utc_now().isoformat()
    try:
        with _db() as con:
            row = con.execute(
                """
                SELECT tenant_id, device_id
                FROM authorized_devices
                WHERE token_hash = ? AND status = 'active' AND revoked_at IS NULL
                """,
                (token_hash,),
            ).fetchone()
            if row is None:
                return False
            con.execute(
                """
                UPDATE authorized_devices
                SET last_seen_at = ?
                WHERE tenant_id = ? AND device_id = ?
                """,
                (now, row["tenant_id"], row["device_id"]),
            )
            con.commit()
            return True
    except sqlite3.Error:
        return False


def _require_api_token(request: Request) -> None:
    if _request_has_api_authorization(request):
        return

    if not _configured_api_token():
        raise HTTPException(status_code=503, detail="OpenIRN API token is not configured on the server")

    raise HTTPException(status_code=403, detail="Invalid API token or expired session")


def _require_sync_read_access(request: Request, tenant_id: str) -> None:
    """Authorize read-only synchronization endpoints.

    OpenIRN v0.3.x is migrating away from persistent client-side secrets.
    Background connectivity checks and SSE listeners therefore must be allowed
    for an enrolled, active terminal identified by X-OpenIRN-Device-Id, even
    when no short-lived user session is currently stored in memory.
    Mutating endpoints continue to require a bearer/session token.
    """
    if _request_has_api_authorization(request):
        return

    _require_active_device(request, tenant_id)


def _pin_hash(pin: str, salt: str, iterations: int = PIN_ITERATIONS) -> str:
    return hashlib.pbkdf2_hmac(
        "sha256",
        str(pin or "").encode("utf-8"),
        salt.encode("utf-8"),
        iterations,
    ).hex()


@contextmanager
def _db() -> Iterator[sqlite3.Connection]:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    try:
        con.execute("PRAGMA foreign_keys = ON")
        con.execute("PRAGMA journal_mode = WAL")
        yield con
    finally:
        con.close()


def _apply_schema() -> None:
    if not SCHEMA_PATH.exists():
        raise RuntimeError(f"OpenIRN SQLite schema not found: {SCHEMA_PATH}")
    with _db() as con:
        con.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))


@app.on_event("startup")
def _startup() -> None:
    _apply_schema()


def _ensure_tenant(con: sqlite3.Connection, tenant_id: str) -> None:
    now = _utc_now().isoformat()
    con.execute(
        """
        INSERT INTO tenants(id, created_at, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at
        """,
        (tenant_id, now, now),
    )


def _device_from_row(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "tenantId": row["tenant_id"],
        "deviceId": row["device_id"],
        "name": row["name"],
        "platform": row["platform"],
        "status": row["status"],
        "createdAt": row["created_at"],
        "lastSeenAt": row["last_seen_at"],
        "revokedAt": row["revoked_at"],
        "invitedByUserId": row["invited_by_user_id"],
        "enrollmentId": row["enrollment_id"],
    }


def _record_device_audit(
    con: sqlite3.Connection,
    tenant_id: str,
    event_type: str,
    *,
    device_id: str | None = None,
    payload: dict[str, Any] | None = None,
) -> None:
    con.execute(
        """
        INSERT INTO device_audit_log(tenant_id, device_id, event_type, created_at, payload_json)
        VALUES (?, ?, ?, ?, ?)
        """,
        (
            tenant_id,
            device_id,
            event_type,
            _utc_now().isoformat(),
            _canonical_json(payload or {}),
        ),
    )


def _create_device(
    con: sqlite3.Connection,
    tenant_id: str,
    *,
    name: str,
    platform: str = "",
    invited_by_user_id: str = "",
    enrollment_id: str = "",
) -> tuple[dict[str, Any], str]:
    device_id = f"device_{uuid.uuid4().hex}"
    token = _new_device_token()
    now = _utc_now().isoformat()
    clean_name = str(name or "").strip()[:120] or "Terminal OpenIRN"
    clean_platform = str(platform or "").strip()[:80]
    con.execute(
        """
        INSERT INTO authorized_devices(
            tenant_id, device_id, name, platform, token_hash, status,
            created_at, last_seen_at, revoked_at, invited_by_user_id, enrollment_id
        ) VALUES (?, ?, ?, ?, ?, 'active', ?, ?, NULL, ?, ?)
        """,
        (
            tenant_id,
            device_id,
            clean_name,
            clean_platform,
            _secret_hash(token),
            now,
            now,
            str(invited_by_user_id or "").strip(),
            str(enrollment_id or "").strip(),
        ),
    )
    _record_device_audit(
        con,
        tenant_id,
        "device.created",
        device_id=device_id,
        payload={
            "name": clean_name,
            "platform": clean_platform,
            "invitedByUserId": invited_by_user_id or "",
            "enrollmentId": enrollment_id or "",
        },
    )
    row = con.execute(
        """
        SELECT tenant_id, device_id, name, platform, status, created_at,
               last_seen_at, revoked_at, invited_by_user_id, enrollment_id
        FROM authorized_devices
        WHERE tenant_id = ? AND device_id = ?
        """,
        (tenant_id, device_id),
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=500, detail="Device creation failed")
    return (_device_from_row(row), token)


def _list_devices(con: sqlite3.Connection, tenant_id: str) -> list[dict[str, Any]]:
    rows = con.execute(
        """
        SELECT tenant_id, device_id, name, platform, status, created_at,
               last_seen_at, revoked_at, invited_by_user_id, enrollment_id
        FROM authorized_devices
        WHERE tenant_id = ?
        ORDER BY status ASC, COALESCE(last_seen_at, created_at) DESC, name ASC
        """,
        (tenant_id,),
    ).fetchall()
    return [_device_from_row(row) for row in rows]


ADRI_PILLAR_RE = re.compile(r"^RES-[1-8]$")
ADRI_CRITERION_RE = re.compile(r"^(RES-[1-8])([.-])([0-9]+)$")
ADRI_VERSION_RE = re.compile(r"(?:Questionnaire_IRN|Référentiel\s+IRN)_v\.?([0-9]+(?:\.[0-9]+)*)\.xlsx$", re.IGNORECASE)

ADRI_DEFAULT_PILLAR_LABELS = {
    "RES-1": "Résilience stratégique",
    "RES-2": "Résilience économique et juridique",
    "RES-3": "Résilience Data & IA",
    "RES-4": "Résilience opérationnelle",
    "RES-5": "Résilience Supply-Chain",
    "RES-6": "Résilience Technologique",
    "RES-7": "Sécurité & Résilience",
    "RES-8": "Résilience Environnementale et énergétique",
}

ADRI_EXPECTED_HEADERS = {
    "Dimension": "pillarId",
    "ID": "sourceCode",
    "Intitulé du critère": "label",
    "Critère": "shortLabel",
    "Description (objectif)": "description",
    "Portée du critère": "sourceScope",
    "Références réglementaires (TBD)": "regulatoryReferences",
    "Recommandations": "recommendations",
}


def _adri_version_from_filename(name: str) -> str:
    match = ADRI_VERSION_RE.search(str(name or ""))
    return f"v{match.group(1)}" if match else "unknown"


def _adri_version_key(version: str) -> tuple[int, ...]:
    raw = str(version or "").lower().lstrip("v")
    parts = []
    for item in raw.split("."):
        try:
            parts.append(int(item))
        except ValueError:
            parts.append(0)
    return tuple(parts or [0])


def _adri_safe_filename(value: str) -> str:
    cleaned = str(value or "").lower().replace(".", "_").replace("-", "_")
    cleaned = re.sub(r"[^a-z0-9_]+", "_", cleaned)
    return re.sub(r"_+", "_", cleaned).strip("_") or "adri_irn"


def _adri_norm(value: Any) -> str:
    return "" if value is None else str(value).strip()


def _adri_clean_multiline(value: Any) -> str:
    return re.sub(r"\s+", " ", _adri_norm(value)).strip()


def _adri_normalize_code(value: Any) -> str:
    raw = _adri_norm(value)
    match = ADRI_CRITERION_RE.match(raw)
    if not match:
        return raw
    return f"{match.group(1)}.{match.group(3)}"


def _adri_scope_from_label(value: Any) -> str:
    raw = _adri_norm(value).lower()
    if "actif" in raw:
        return "asset"
    if "système" in raw or "systeme" in raw:
        return "criticalSystem"
    if "fonction" in raw:
        return "organization"
    if "organisation" in raw:
        return "organization"
    return "unknown"


def _adri_sort_key(code: str) -> tuple[int, int]:
    criterion_match = ADRI_CRITERION_RE.match(str(code or ""))
    if criterion_match:
        return int(criterion_match.group(1).split("-")[1]), int(criterion_match.group(3))
    pillar_match = re.match(r"^RES-([1-8])$", str(code or ""))
    if pillar_match:
        return int(pillar_match.group(1)), 0
    return 99, 99


def _adri_find_header_row(ws: Any) -> tuple[int, dict[int, str]]:
    for row_index, row in enumerate(ws.iter_rows(values_only=True), start=1):
        values = [_adri_norm(value) for value in row]
        if "Dimension" in values and "ID" in values and "Intitulé du critère" in values:
            return row_index, {index: value for index, value in enumerate(values) if value}
    raise HTTPException(status_code=422, detail=f"Ligne d'en-tête introuvable dans l'onglet {ws.title!r}")


def _adri_parse_pillar_labels_from_grid(wb: Any) -> dict[str, str]:
    labels = dict(ADRI_DEFAULT_PILLAR_LABELS)
    if "Grille V1" not in wb.sheetnames:
        return labels
    ws = wb["Grille V1"]
    for row in ws.iter_rows(values_only=True):
        first_cell = _adri_norm(row[0] if row else None)
        if not first_cell or "RES-" not in first_cell:
            continue
        match = re.search(r"(RES-[1-8])", first_cell)
        if not match:
            continue
        code = match.group(1)
        label = re.sub(r"\(?\s*RES-[1-8]\s*\)?", "", first_cell)
        label = _adri_clean_multiline(label)
        if label:
            labels[code] = label
    return labels


def _adri_parse_workbook(raw_xlsx: bytes, *, version: str, remote: dict[str, Any]) -> dict[str, Any]:
    try:
        from openpyxl import load_workbook
    except ImportError as exc:
        raise HTTPException(status_code=503, detail="La dépendance Python openpyxl est requise pour importer le référentiel officiel") from exc

    wb = load_workbook(BytesIO(raw_xlsx), data_only=True, read_only=True)
    if "Référentiel v1" not in wb.sheetnames:
        raise HTTPException(status_code=422, detail="Onglet 'Référentiel v1' introuvable dans le fichier officiel")

    warnings: list[str] = []
    pillar_labels = _adri_parse_pillar_labels_from_grid(wb)
    ws = wb["Référentiel v1"]
    header_row, header_by_index = _adri_find_header_row(ws)
    criteria_by_code: dict[str, dict[str, Any]] = {}
    seen_source_codes: set[str] = set()

    for row_number, row in enumerate(ws.iter_rows(min_row=header_row + 1, values_only=True), start=header_row + 1):
        raw: dict[str, str] = {}
        for index, header in header_by_index.items():
            if header in ADRI_EXPECTED_HEADERS:
                raw[ADRI_EXPECTED_HEADERS[header]] = _adri_norm(row[index] if index < len(row) else None)

        source_code = raw.get("sourceCode", "")
        if not ADRI_CRITERION_RE.match(source_code):
            continue

        code = _adri_normalize_code(source_code)
        pillar_id = raw.get("pillarId") or code.split(".")[0]
        if not ADRI_PILLAR_RE.match(pillar_id):
            warnings.append(f"Ligne {row_number}: dimension invalide {pillar_id!r} pour {source_code}")
            pillar_id = code.split(".")[0]

        if source_code != code:
            warnings.append(f"Ligne {row_number}: identifiant normalisé {source_code!r} -> {code!r}")
        if source_code in seen_source_codes:
            warnings.append(f"Ligne {row_number}: doublon sourceCode {source_code!r}")
        seen_source_codes.add(source_code)

        label = _adri_clean_multiline(raw.get("label", "")) or _adri_clean_multiline(raw.get("shortLabel", ""))
        if not label:
            warnings.append(f"Ligne {row_number}: critère {code} sans libellé")

        criteria_by_code[code] = {
            "id": code,
            "code": code,
            "sourceCode": source_code,
            "pillarId": pillar_id,
            "label": label,
            "shortLabel": _adri_clean_multiline(raw.get("shortLabel", "")),
            "description": _adri_clean_multiline(raw.get("description", "")),
            "scope": _adri_scope_from_label(raw.get("sourceScope", "")),
            "sourceScope": _adri_clean_multiline(raw.get("sourceScope", "")),
            "answerMode": "R_NR",
            "regulatoryReferences": _adri_clean_multiline(raw.get("regulatoryReferences", "")),
            "recommendations": _adri_clean_multiline(raw.get("recommendations", "")),
            "active": True,
            "source": {"sheet": ws.title, "row": row_number},
        }

    pillars = [
        {"id": code, "code": code, "label": pillar_labels.get(code, code)}
        for code in sorted(pillar_labels.keys(), key=_adri_sort_key)
        if ADRI_PILLAR_RE.match(code)
    ]
    criteria = sorted(criteria_by_code.values(), key=lambda criterion: _adri_sort_key(criterion["code"]))

    if len(pillars) != 8:
        warnings.append(f"Nombre de piliers inattendu: {len(pillars)} au lieu de 8")
    if not criteria:
        warnings.append("Aucun critère extrait: vérifier la structure du fichier officiel et le mapping des colonnes")

    return {
        "id": f"adri-irn-{version}",
        "version": version,
        "importedAt": _utc_now().isoformat(),
        "source": {
            "type": "gitlab",
            "url": OFFICIAL_ADRI_SOURCE_URL,
            "projectPath": OFFICIAL_ADRI_PROJECT_PATH,
            "defaultBranch": remote.get("defaultBranch") or OFFICIAL_ADRI_DEFAULT_BRANCH,
            "filePath": remote.get("filePath") or "",
            "commitSha": remote.get("blobId") or "",
            "blobId": remote.get("blobId") or "",
            "checksumSha256": hashlib.sha256(raw_xlsx).hexdigest(),
            "license": OFFICIAL_ADRI_LICENSE,
        },
        "pillars": pillars,
        "criteria": criteria,
        "importWarnings": [
            "Référentiel officiel téléchargé depuis le dépôt public aDRI IRN.",
            "Le serveur conserve une copie canonique JSON pour OpenIRN.",
            *warnings,
        ],
    }


def _adri_validation_report(referential: dict[str, Any]) -> dict[str, Any]:
    errors: list[dict[str, Any]] = []
    warnings: list[dict[str, Any]] = []
    pillars = referential.get("pillars") if isinstance(referential.get("pillars"), list) else []
    criteria = referential.get("criteria") if isinstance(referential.get("criteria"), list) else []
    if len(pillars) != 8:
        errors.append({"code": "unexpected_pillar_count", "message": "Le référentiel doit contenir 8 piliers.", "found": len(pillars)})
    if not criteria:
        errors.append({"code": "no_criteria", "message": "Aucun critère n'a été extrait du référentiel."})

    pillar_ids = {str(pillar.get("id") or pillar.get("code") or "") for pillar in pillars if isinstance(pillar, dict)}
    criterion_codes: set[str] = set()
    for criterion in criteria:
        if not isinstance(criterion, dict):
            continue
        code = str(criterion.get("code") or criterion.get("id") or "")
        if not re.match(r"^RES-[1-8]\.[0-9]+$", code):
            errors.append({"code": "invalid_criterion_code", "message": "Code critère invalide.", "criterion": code})
            continue
        if code in criterion_codes:
            errors.append({"code": "duplicate_criterion_code", "message": "Code critère dupliqué.", "criterion": code})
        criterion_codes.add(code)
        pillar_id = str(criterion.get("pillarId") or "")
        if pillar_id not in pillar_ids:
            errors.append({"code": "unknown_pillar", "message": "Le critère référence un pilier inconnu.", "criterion": code, "pillarId": pillar_id})
        if not str(criterion.get("label") or "").strip():
            warnings.append({"code": "missing_label", "message": "Libellé critère absent.", "criterion": code})

    status = "failed" if errors else ("passed_with_warnings" if warnings else "passed")
    return {
        "status": status,
        "generatedAt": _utc_now().isoformat(),
        "errors": errors,
        "warnings": warnings,
        "summary": {
            "referentialId": referential.get("id"),
            "version": referential.get("version"),
            "pillars": len(pillars),
            "criteria": len(criteria),
        },
    }


def _gitlab_quote(value: str) -> str:
    return urllib.parse.quote(str(value), safe="")


def _gitlab_request_json(path: str, query: dict[str, str] | None = None) -> Any:
    query_string = f"?{urllib.parse.urlencode(query or {})}" if query else ""
    url = f"{OFFICIAL_ADRI_GITLAB_API}{path}{query_string}"
    request = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "OpenIRN"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            raw = response.read()
    except urllib.error.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"GitLab a répondu HTTP {exc.code} pour {url}") from exc
    except urllib.error.URLError as exc:
        raise HTTPException(status_code=502, detail=f"GitLab est injoignable: {exc.reason}") from exc
    try:
        return json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=502, detail="Réponse GitLab JSON invalide") from exc


def _gitlab_request_bytes(path: str, query: dict[str, str] | None = None) -> bytes:
    query_string = f"?{urllib.parse.urlencode(query or {})}" if query else ""
    url = f"{OFFICIAL_ADRI_GITLAB_API}{path}{query_string}"
    request = urllib.request.Request(url, headers={"Accept": "application/octet-stream", "User-Agent": "OpenIRN"})
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            return response.read()
    except urllib.error.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Téléchargement GitLab refusé HTTP {exc.code} pour {url}") from exc
    except urllib.error.URLError as exc:
        raise HTTPException(status_code=502, detail=f"GitLab est injoignable: {exc.reason}") from exc


def _gitlab_repository_tree(
    project_id: str,
    *,
    tree_path: str,
    ref: str,
    recursive: bool = False,
) -> list[dict[str, Any]]:
    query = {
        "ref": ref,
        "per_page": "100",
    }
    if tree_path:
        query["path"] = tree_path
    if recursive:
        query["recursive"] = "true"

    tree = _gitlab_request_json(
        f"/projects/{project_id}/repository/tree",
        query,
    )
    if not isinstance(tree, list):
        raise HTTPException(status_code=502, detail="Réponse GitLab repository/tree invalide")
    return [item for item in tree if isinstance(item, dict)]


def _official_remote_latest() -> dict[str, Any]:
    project_id = _gitlab_quote(OFFICIAL_ADRI_PROJECT_PATH)
    project = _gitlab_request_json(f"/projects/{project_id}")
    default_branch = str(project.get("default_branch") or OFFICIAL_ADRI_DEFAULT_BRANCH)

    candidate_tree_paths = [
        OFFICIAL_ADRI_TREE_PATH,
        "Référentiel d'évaluation IRN (FR)",
        "Grille d'évaluation IRN (FR)/xlsx",
        "",
    ]

    seen_paths: set[str] = set()
    candidates: list[dict[str, Any]] = []
    last_error: HTTPException | None = None

    for tree_path in candidate_tree_paths:
        if tree_path in seen_paths:
            continue
        seen_paths.add(tree_path)

        try:
            tree = _gitlab_repository_tree(
                project_id,
                tree_path=tree_path,
                ref=default_branch,
                recursive=True,
            )
        except HTTPException as exc:
            last_error = exc
            detail = str(exc.detail)
            if "HTTP 404" in detail or exc.status_code == 404:
                continue
            raise

        for item in tree:
            if item.get("type") != "blob":
                continue
            name = str(item.get("name") or "")
            if not ADRI_VERSION_RE.search(name):
                continue
            version = _adri_version_from_filename(name)
            file_path = str(item.get("path") or "")
            candidates.append({
                "version": version,
                "fileName": name,
                "filePath": file_path,
                "blobId": str(item.get("id") or ""),
                "defaultBranch": default_branch,
                "projectPath": OFFICIAL_ADRI_PROJECT_PATH,
                "sourceUrl": OFFICIAL_ADRI_SOURCE_URL,
                "webUrl": f"{OFFICIAL_ADRI_SOURCE_URL}/-/blob/{urllib.parse.quote(default_branch, safe='')}/{urllib.parse.quote(file_path)}",
            })

        if candidates:
            break

    if not candidates:
        if last_error is not None:
            detail = str(last_error.detail)
            if "HTTP 404" in detail:
                detail = (
                    "Le chemin GitLab configuré pour le référentiel aDRI est introuvable. "
                    "Le dépôt officiel utilise maintenant le dossier "
                    "Référentiel d'évaluation IRN (FR)/V1. "
                    "Vérifiez OPENIRN_ADRI_TREE_PATH si cette variable est définie."
                )
                raise HTTPException(status_code=404, detail=detail) from last_error
        raise HTTPException(
            status_code=404,
            detail="Aucun fichier Référentiel IRN_v*.xlsx ou Questionnaire_IRN_v*.xlsx trouvé dans le dépôt aDRI",
        )
    candidates.sort(key=lambda item: _adri_version_key(str(item.get("version") or "")), reverse=True)
    return candidates[0]


def _download_official_adri_xlsx(remote: dict[str, Any]) -> bytes:
    project_id = _gitlab_quote(OFFICIAL_ADRI_PROJECT_PATH)
    file_path = _gitlab_quote(str(remote.get("filePath") or ""))
    raw = _gitlab_request_bytes(
        f"/projects/{project_id}/repository/files/{file_path}/raw",
        {"ref": str(remote.get("defaultBranch") or OFFICIAL_ADRI_DEFAULT_BRANCH)},
    )
    if len(raw) < 1024 or not raw.startswith(b"PK"):
        raise HTTPException(status_code=502, detail="Le fichier téléchargé depuis GitLab ne ressemble pas à un fichier XLSX valide")
    return raw


def _official_referential_summary_from_row(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    report = _parse_json(row["validation_report_json"], {})
    return {
        "referentialId": row["referential_id"],
        "version": row["version"],
        "active": bool(row["active"]),
        "sourceUrl": row["source_url"],
        "projectPath": row["project_path"],
        "defaultBranch": row["default_branch"],
        "filePath": row["file_path"],
        "sourceBlobId": row["source_blob_id"],
        "sourceSha256": row["source_sha256"],
        "canonicalSha256": row["canonical_sha256"],
        "downloadedAt": row["downloaded_at"],
        "importedAt": row["imported_at"],
        "pillarCount": row["pillar_count"],
        "criterionCount": row["criterion_count"],
        "validationStatus": report.get("status") if isinstance(report, dict) else "unknown",
    }


def _load_current_official_referential(con: sqlite3.Connection, tenant_id: str) -> sqlite3.Row | None:
    return con.execute(
        """
        SELECT tenant_id, referential_id, version, active, source_url, project_path,
               default_branch, file_path, source_blob_id, source_sha256,
               canonical_sha256, downloaded_at, imported_at, pillar_count,
               criterion_count, import_warnings_json, validation_report_json, payload_json
        FROM official_referentials
        WHERE tenant_id = ? AND active = 1
        ORDER BY imported_at DESC
        LIMIT 1
        """,
        (tenant_id,),
    ).fetchone()


def _store_official_referential(
    con: sqlite3.Connection,
    tenant_id: str,
    referential: dict[str, Any],
    remote: dict[str, Any],
    report: dict[str, Any],
    raw_xlsx: bytes,
) -> dict[str, Any]:
    referential_id = str(referential.get("id") or "adri-irn")
    source = referential.get("source") if isinstance(referential.get("source"), dict) else {}
    source_sha256 = hashlib.sha256(raw_xlsx).hexdigest()
    canonical_sha256 = _json_sha256(referential)
    downloaded_at = _utc_now().isoformat()
    imported_at = str(referential.get("importedAt") or downloaded_at)
    pillars = referential.get("pillars") if isinstance(referential.get("pillars"), list) else []
    criteria = referential.get("criteria") if isinstance(referential.get("criteria"), list) else []

    output_dir = OFFICIAL_REFERENTIAL_DIR / _safe_segment(tenant_id, "default") / _adri_safe_filename(referential_id)
    output_dir.mkdir(parents=True, exist_ok=True)
    raw_path = output_dir / str(remote.get("fileName") or "Questionnaire_IRN.xlsx")
    json_path = output_dir / f"{_adri_safe_filename(referential_id)}.json"
    report_path = output_dir / f"{_adri_safe_filename(referential_id)}_validation.json"
    raw_path.write_bytes(raw_xlsx)
    json_path.write_text(_pretty_json(referential) + "\n", encoding="utf-8")
    report_path.write_text(_pretty_json(report) + "\n", encoding="utf-8")

    con.execute("UPDATE official_referentials SET active = 0 WHERE tenant_id = ?", (tenant_id,))
    con.execute(
        """
        INSERT INTO official_referentials(
            tenant_id, referential_id, version, active, source_url, project_path,
            default_branch, file_path, source_blob_id, source_sha256,
            canonical_sha256, downloaded_at, imported_at, pillar_count,
            criterion_count, import_warnings_json, validation_report_json, payload_json
        ) VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(tenant_id, referential_id) DO UPDATE SET
            version = excluded.version,
            active = 1,
            source_url = excluded.source_url,
            project_path = excluded.project_path,
            default_branch = excluded.default_branch,
            file_path = excluded.file_path,
            source_blob_id = excluded.source_blob_id,
            source_sha256 = excluded.source_sha256,
            canonical_sha256 = excluded.canonical_sha256,
            downloaded_at = excluded.downloaded_at,
            imported_at = excluded.imported_at,
            pillar_count = excluded.pillar_count,
            criterion_count = excluded.criterion_count,
            import_warnings_json = excluded.import_warnings_json,
            validation_report_json = excluded.validation_report_json,
            payload_json = excluded.payload_json
        """,
        (
            tenant_id,
            referential_id,
            str(referential.get("version") or "unknown"),
            str(source.get("url") or OFFICIAL_ADRI_SOURCE_URL),
            str(source.get("projectPath") or OFFICIAL_ADRI_PROJECT_PATH),
            str(source.get("defaultBranch") or remote.get("defaultBranch") or OFFICIAL_ADRI_DEFAULT_BRANCH),
            str(source.get("filePath") or remote.get("filePath") or ""),
            str(source.get("blobId") or remote.get("blobId") or ""),
            source_sha256,
            canonical_sha256,
            downloaded_at,
            imported_at,
            len(pillars),
            len(criteria),
            _canonical_json(referential.get("importWarnings") if isinstance(referential.get("importWarnings"), list) else []),
            _canonical_json(report),
            _canonical_json(referential),
        ),
    )
    return {
        "referentialId": referential_id,
        "version": referential.get("version") or "unknown",
        "sourceSha256": source_sha256,
        "canonicalSha256": canonical_sha256,
        "downloadedAt": downloaded_at,
        "importedAt": imported_at,
        "pillarCount": len(pillars),
        "criterionCount": len(criteria),
        "validationStatus": report.get("status"),
        "storedFiles": {
            "xlsx": str(raw_path),
            "json": str(json_path),
            "validation": str(report_path),
        },
    }


def _role_normalize(value: Any) -> str:
    role = str(value or "reader").strip().lower()
    aliases = {
        "admin": "administrator",
        "administrateur": "administrator",
        "administrator": "administrator",
        "pilote": "campaign_manager",
        "pilote_irn": "campaign_manager",
        "campaignmanager": "campaign_manager",
        "campaign_manager": "campaign_manager",
        "evaluateur": "evaluator",
        "évaluateur": "evaluator",
        "evaluator": "evaluator",
        "validateur": "reviewer",
        "validator": "reviewer",
        "reviewer": "reviewer",
        "lecteur": "reader",
        "reader": "reader",
    }
    return aliases.get(role, "reader")


def _sanitize_user(raw_user: Any) -> dict[str, Any] | None:
    if not isinstance(raw_user, dict):
        return None

    user_id = str(raw_user.get("id") or "").strip()
    if not user_id:
        return None

    created_at = str(raw_user.get("createdAt") or _utc_now().isoformat())
    updated_at = str(raw_user.get("updatedAt") or created_at)
    active = raw_user.get("active")

    return {
        "id": user_id,
        "firstName": str(raw_user.get("firstName") or "").strip(),
        "lastName": str(raw_user.get("lastName") or "").strip(),
        "email": str(raw_user.get("email") or "").strip().lower(),
        "role": _role_normalize(raw_user.get("role") or raw_user.get("roleLabel")),
        "active": active if isinstance(active, bool) else True,
        "createdAt": created_at,
        "updatedAt": updated_at,
    }


def _sort_users(users: list[dict[str, Any]]) -> list[dict[str, Any]]:
    def key(user: dict[str, Any]) -> tuple[int, str]:
        active_weight = 0 if user.get("active") is True else 1
        display = " ".join(
            part
            for part in [
                str(user.get("firstName") or "").strip(),
                str(user.get("lastName") or "").strip(),
                str(user.get("email") or "").strip(),
                str(user.get("id") or "").strip(),
            ]
            if part
        ).lower()
        return (active_weight, display)

    return sorted(users, key=key)


def _row_to_user(row: sqlite3.Row) -> dict[str, Any]:
    payload = _parse_json(row["payload_json"], {})
    if not isinstance(payload, dict):
        payload = {}
    payload.update(
        {
            "id": row["user_id"],
            "firstName": row["first_name"],
            "lastName": row["last_name"],
            "email": row["email"],
            "role": row["role"],
            "active": bool(row["active"]),
            "createdAt": row["created_at"],
            "updatedAt": row["updated_at"],
        }
    )
    return payload


def _load_central_users(con: sqlite3.Connection, tenant_id: str) -> list[dict[str, Any]]:
    rows = con.execute(
        """
        SELECT tenant_id, user_id, first_name, last_name, email, role,
               active, created_at, updated_at, payload_json
        FROM users
        WHERE tenant_id = ?
        """,
        (tenant_id,),
    ).fetchall()
    return _sort_users([_row_to_user(row) for row in rows])


def _save_user(con: sqlite3.Connection, tenant_id: str, user: dict[str, Any]) -> None:
    con.execute(
        """
        INSERT INTO users(
            tenant_id, user_id, first_name, last_name, email, role,
            active, created_at, updated_at, payload_json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(tenant_id, user_id) DO UPDATE SET
            first_name = excluded.first_name,
            last_name = excluded.last_name,
            email = excluded.email,
            role = excluded.role,
            active = excluded.active,
            updated_at = excluded.updated_at,
            payload_json = excluded.payload_json
        """,
        (
            tenant_id,
            user["id"],
            user["firstName"],
            user["lastName"],
            user["email"],
            user["role"],
            1 if user["active"] else 0,
            user["createdAt"],
            user["updatedAt"],
            _canonical_json(user),
        ),
    )


def _ensure_user_credentials(con: sqlite3.Connection, tenant_id: str, users: list[dict[str, Any]]) -> None:
    for user in users:
        user_id = str(user.get("id") or "").strip()
        if not user_id:
            continue
        exists = con.execute(
            "SELECT 1 FROM user_credentials WHERE tenant_id = ? AND user_id = ?",
            (tenant_id, user_id),
        ).fetchone()
        if exists:
            continue
        salt = uuid.uuid4().hex
        con.execute(
            """
            INSERT INTO user_credentials(
                tenant_id, user_id, algorithm, iterations, salt, pin_hash,
                requires_change, updated_at
            ) VALUES (?, ?, 'pbkdf2_sha256', ?, ?, ?, 1, ?)
            """,
            (tenant_id, user_id, PIN_ITERATIONS, salt, _pin_hash(PIN_DEFAULT, salt, PIN_ITERATIONS), _utc_now().isoformat()),
        )


def _merge_central_users(con: sqlite3.Connection, tenant_id: str, raw_users: Any) -> int:
    if not isinstance(raw_users, list):
        return 0

    current = {user["id"]: user for user in _load_central_users(con, tenant_id)}
    changed = 0
    for raw_user in raw_users:
        user = _sanitize_user(raw_user)
        if not user:
            continue
        existing = current.get(user["id"])
        if existing is None or _parse_datetime(user.get("updatedAt")) >= _parse_datetime(existing.get("updatedAt")):
            _save_user(con, tenant_id, user)
            current[user["id"]] = user
            changed += 1

    if changed:
        _ensure_user_credentials(con, tenant_id, list(current.values()))
    return changed


def _set_user_pin(con: sqlite3.Connection, tenant_id: str, user_id: str, pin: str, *, requires_change: bool) -> None:
    cleaned_pin = str(pin or "").strip()
    if len(cleaned_pin) < 4 or len(cleaned_pin) > 32:
        raise HTTPException(status_code=400, detail="PIN must contain between 4 and 32 characters")

    user_exists = con.execute(
        "SELECT 1 FROM users WHERE tenant_id = ? AND user_id = ?",
        (tenant_id, user_id),
    ).fetchone()
    if not user_exists:
        raise HTTPException(status_code=404, detail="Unknown user")

    salt = uuid.uuid4().hex
    con.execute(
        """
        INSERT INTO user_credentials(
            tenant_id, user_id, algorithm, iterations, salt, pin_hash,
            requires_change, updated_at
        ) VALUES (?, ?, 'pbkdf2_sha256', ?, ?, ?, ?, ?)
        ON CONFLICT(tenant_id, user_id) DO UPDATE SET
            algorithm = excluded.algorithm,
            iterations = excluded.iterations,
            salt = excluded.salt,
            pin_hash = excluded.pin_hash,
            requires_change = excluded.requires_change,
            updated_at = excluded.updated_at
        """,
        (
            tenant_id,
            user_id,
            PIN_ITERATIONS,
            salt,
            _pin_hash(cleaned_pin, salt, PIN_ITERATIONS),
            1 if requires_change else 0,
            _utc_now().isoformat(),
        ),
    )


def _verify_user_pin(con: sqlite3.Connection, tenant_id: str, user_id: str, pin: str) -> tuple[bool, bool]:
    credential = con.execute(
        """
        SELECT salt, pin_hash, iterations, requires_change
        FROM user_credentials
        WHERE tenant_id = ? AND user_id = ?
        """,
        (tenant_id, user_id),
    ).fetchone()
    if credential is None:
        users = _load_central_users(con, tenant_id)
        _ensure_user_credentials(con, tenant_id, users)
        credential = con.execute(
            """
            SELECT salt, pin_hash, iterations, requires_change
            FROM user_credentials
            WHERE tenant_id = ? AND user_id = ?
            """,
            (tenant_id, user_id),
        ).fetchone()
    if credential is None:
        return (False, False)

    salt = str(credential["salt"] or "")
    expected_hash = str(credential["pin_hash"] or "")
    iterations = int(credential["iterations"] or PIN_ITERATIONS)
    if not salt or not expected_hash:
        return (False, False)

    provided_hash = _pin_hash(str(pin or "").strip(), salt, iterations)
    accepted = hmac.compare_digest(provided_hash, expected_hash)
    return (accepted, bool(credential["requires_change"]))


def _campaign_record(raw_campaign: dict[str, Any]) -> dict[str, Any]:
    nested = raw_campaign.get("campaign")
    if isinstance(nested, dict):
        return nested
    return raw_campaign


def _campaign_id(raw_campaign: dict[str, Any]) -> str | None:
    campaign = _campaign_record(raw_campaign)
    for source in (campaign, raw_campaign):
        for key in ("id", "campaignId"):
            value = str(source.get(key) or "").strip()
            if value:
                return value
    return None


def _campaign_updated_at(raw_campaign: dict[str, Any], payload: dict[str, Any], received_at: str) -> str:
    campaign = _campaign_record(raw_campaign)
    for source in (campaign, raw_campaign, payload):
        for key in ("updatedAt", "lastUpdatedAt", "modifiedAt", "createdAt", "generatedAt"):
            value = source.get(key)
            if value:
                return str(value)
    return received_at


def _looks_like_campaign_snapshot(item: Any) -> bool:
    if not isinstance(item, dict):
        return False
    if _campaign_id(item):
        return True
    nested = item.get("campaign")
    return isinstance(nested, dict) and _campaign_id(nested) is not None


def _extract_campaigns(payload: dict[str, Any]) -> list[dict[str, Any]]:
    direct = payload.get("campaigns")
    if isinstance(direct, list):
        return [item for item in direct if isinstance(item, dict)]

    found: list[dict[str, Any]] = []

    def walk(value: Any) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                if key == "campaigns" and isinstance(child, list):
                    for item in child:
                        if _looks_like_campaign_snapshot(item):
                            found.append(item)
                else:
                    walk(child)
        elif isinstance(value, list):
            for item in value:
                walk(item)

    walk(payload)
    return found


def _record_campaign_revisions(
    con: sqlite3.Connection,
    tenant_id: str,
    server_sync_id: str,
    device_id: str,
    received_at: str,
    payload: dict[str, Any],
) -> dict[str, int]:
    campaigns = _extract_campaigns(payload)
    revision_count = 0
    conflict_count = 0
    skipped_without_id = 0
    deleted_count = 0
    received_campaign_ids: set[str] = set()

    for raw_campaign in campaigns:
        cid = _campaign_id(raw_campaign)
        if not cid:
            skipped_without_id += 1
            continue
        received_campaign_ids.add(cid)

        campaign_payload_sha256 = _json_sha256(raw_campaign)
        updated_at = _campaign_updated_at(raw_campaign, payload, received_at)
        existing = con.execute(
            """
            SELECT server_revision, payload_sha256, device_id, received_at
            FROM campaign_states
            WHERE tenant_id = ? AND campaign_id = ?
            """,
            (tenant_id, cid),
        ).fetchone()

        if existing and str(existing["payload_sha256"]) == campaign_payload_sha256:
            continue

        next_revision = 1
        conflict_detected = 0
        conflict_reason = None
        if existing:
            next_revision = int(existing["server_revision"] or 0) + 1
            if str(existing["device_id"] or "") != device_id:
                conflict_detected = 1
                conflict_reason = "last_write_wins_over_previous_device_revision"
            elif _parse_datetime(existing["received_at"]) > _parse_datetime(received_at):
                conflict_detected = 1
                conflict_reason = "older_received_at_after_newer_state"

        if conflict_detected:
            conflict_count += 1

        con.execute(
            """
            INSERT INTO campaign_revisions(
                tenant_id, campaign_id, server_revision, server_sync_id,
                device_id, updated_at, received_at, payload_sha256,
                payload_json, conflict_policy, conflict_detected, conflict_reason
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'last_write_wins', ?, ?)
            ON CONFLICT(tenant_id, campaign_id, server_revision) DO NOTHING
            """,
            (
                tenant_id,
                cid,
                next_revision,
                server_sync_id,
                device_id,
                updated_at,
                received_at,
                campaign_payload_sha256,
                _canonical_json(raw_campaign),
                conflict_detected,
                conflict_reason,
            ),
        )

        con.execute(
            """
            INSERT INTO campaign_states(
                tenant_id, campaign_id, server_revision, server_sync_id,
                device_id, updated_at, received_at, payload_sha256,
                payload_json, conflict_policy
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'last_write_wins')
            ON CONFLICT(tenant_id, campaign_id) DO UPDATE SET
                server_revision = excluded.server_revision,
                server_sync_id = excluded.server_sync_id,
                device_id = excluded.device_id,
                updated_at = excluded.updated_at,
                received_at = excluded.received_at,
                payload_sha256 = excluded.payload_sha256,
                payload_json = excluded.payload_json,
                conflict_policy = excluded.conflict_policy
            """,
            (
                tenant_id,
                cid,
                next_revision,
                server_sync_id,
                device_id,
                updated_at,
                received_at,
                campaign_payload_sha256,
                _canonical_json(raw_campaign),
            ),
        )

        con.execute(
            """
            INSERT INTO sync_events(
                tenant_id, event_type, server_sync_id, campaign_id,
                device_id, created_at, payload_json
            ) VALUES (?, 'campaign_revision_received', ?, ?, ?, ?, ?)
            """,
            (
                tenant_id,
                server_sync_id,
                cid,
                device_id,
                _utc_now().isoformat(),
                _canonical_json(
                    {
                        "campaignId": cid,
                        "serverRevision": next_revision,
                        "conflictDetected": conflict_detected == 1,
                        "conflictReason": conflict_reason,
                    }
                ),
            ),
        )
        revision_count += 1

    # OpenIRN clients publish the complete campaign set for a tenant.
    # A campaign absent from a new snapshot is therefore considered deleted.
    current_rows = con.execute(
        "SELECT campaign_id FROM campaign_states WHERE tenant_id = ?",
        (tenant_id,),
    ).fetchall()
    deleted_campaign_ids = [
        str(row["campaign_id"] or "")
        for row in current_rows
        if str(row["campaign_id"] or "") and str(row["campaign_id"] or "") not in received_campaign_ids
    ]

    for deleted_campaign_id in deleted_campaign_ids:
        con.execute(
            "DELETE FROM campaign_states WHERE tenant_id = ? AND campaign_id = ?",
            (tenant_id, deleted_campaign_id),
        )
        con.execute(
            "DELETE FROM campaign_revisions WHERE tenant_id = ? AND campaign_id = ?",
            (tenant_id, deleted_campaign_id),
        )
        con.execute(
            "DELETE FROM sync_events WHERE tenant_id = ? AND campaign_id = ?",
            (tenant_id, deleted_campaign_id),
        )
        con.execute(
            """
            INSERT INTO sync_events(
                tenant_id, event_type, server_sync_id, campaign_id,
                device_id, created_at, payload_json
            ) VALUES (?, 'campaign_deleted_by_snapshot_absence', ?, ?, ?, ?, ?)
            """,
            (
                tenant_id,
                server_sync_id,
                deleted_campaign_id,
                device_id,
                _utc_now().isoformat(),
                _canonical_json({"campaignId": deleted_campaign_id}),
            ),
        )
        deleted_count += 1

    return {
        "campaignCount": len(campaigns),
        "revisionCount": revision_count,
        "conflictCount": conflict_count,
        "deletedCount": deleted_count,
        "skippedWithoutId": skipped_without_id,
    }


def _public_snapshot_from_row(row: sqlite3.Row) -> dict[str, Any]:
    payload = _parse_json(row["payload_json"], {})
    return {
        "serverSyncId": row["server_sync_id"],
        "receivedAt": row["received_at"],
        "tenantId": row["tenant_id"],
        "deviceId": row["device_id"],
        "payloadSha256": row["payload_sha256"],
        "campaignCount": int(row["campaign_count"] or 0),
        "payload": payload if isinstance(payload, dict) else None,
    }


def _snapshot_summary_from_row(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    public = _public_snapshot_from_row(row)
    public.pop("payload", None)
    return public


def _campaign_title_from_payload(payload: Any, fallback: str) -> str:
    if not isinstance(payload, dict):
        return fallback
    campaign = _campaign_record(payload)
    for key in ("name", "title", "label"):
        value = str(campaign.get(key) or "").strip()
        if value:
            return value
    return fallback


def _public_campaign_state_from_row(row: sqlite3.Row) -> dict[str, Any]:
    payload = _parse_json(row["payload_json"], {})
    campaign_id = str(row["campaign_id"] or "")
    return {
        "tenantId": row["tenant_id"],
        "campaignId": campaign_id,
        "campaignName": _campaign_title_from_payload(payload, campaign_id),
        "serverRevision": int(row["server_revision"] or 0),
        "serverSyncId": row["server_sync_id"],
        "deviceId": row["device_id"],
        "updatedAt": row["updated_at"],
        "receivedAt": row["received_at"],
        "payloadSha256": row["payload_sha256"],
        "conflictPolicy": row["conflict_policy"],
    }


def _public_campaign_revision_from_row(row: sqlite3.Row, *, include_payload: bool = False) -> dict[str, Any]:
    payload = _parse_json(row["payload_json"], {})
    campaign_id = str(row["campaign_id"] or "")
    public = {
        "tenantId": row["tenant_id"],
        "campaignId": campaign_id,
        "campaignName": _campaign_title_from_payload(payload, campaign_id),
        "serverRevision": int(row["server_revision"] or 0),
        "serverSyncId": row["server_sync_id"],
        "deviceId": row["device_id"],
        "updatedAt": row["updated_at"],
        "receivedAt": row["received_at"],
        "payloadSha256": row["payload_sha256"],
        "conflictPolicy": row["conflict_policy"],
        "conflictDetected": bool(row["conflict_detected"]),
        "conflictReason": row["conflict_reason"],
    }
    if include_payload:
        public["payload"] = payload if isinstance(payload, dict) else None
    return public


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _table_counts(con: sqlite3.Connection) -> dict[str, int | None]:
    counts: dict[str, int | None] = {}
    for table in [
        "tenants",
        "users",
        "sync_snapshots",
        "campaign_states",
        "campaign_revisions",
        "authorized_devices",
        "device_enrollment_codes",
        "device_audit_log",
        "sync_events",
    ]:
        try:
            counts[table] = int(con.execute(f"select count(*) from {table}").fetchone()[0])
        except sqlite3.Error:
            counts[table] = None
    return counts


def _sqlite_integrity_check(path: Path) -> str:
    if not path.exists():
        return "missing"
    try:
        with sqlite3.connect(path) as con:
            row = con.execute("pragma integrity_check").fetchone()
            return str(row[0]) if row else "unknown"
    except sqlite3.Error as exc:
        return f"error: {exc}"


def _backup_metadata_from_file(path: Path) -> dict[str, Any]:
    meta_path = path.with_suffix(path.suffix + ".json")
    metadata = _parse_json(meta_path.read_text(encoding="utf-8") if meta_path.exists() else None, {})
    if not isinstance(metadata, dict):
        metadata = {}

    created_at = metadata.get("createdAt")
    if not created_at:
        created_at = datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat()

    sha256 = str(metadata.get("sha256") or "").strip()
    if not sha256:
        sha_path = path.with_suffix(path.suffix + ".sha256")
        if sha_path.exists():
            sha_parts = sha_path.read_text(encoding="utf-8").split()
            sha256 = sha_parts[0] if sha_parts else ""

    return {
        "name": path.name,
        "path": str(path),
        "createdAt": created_at,
        "sizeBytes": path.stat().st_size,
        "sha256": sha256,
        "counts": metadata.get("counts") if isinstance(metadata.get("counts"), dict) else {},
    }


def _list_backups(limit: int = 10) -> list[dict[str, Any]]:
    if not BACKUP_DIR.exists():
        return []
    backups = sorted(
        BACKUP_DIR.glob("openirn-*.sqlite3"),
        key=lambda item: item.stat().st_mtime,
        reverse=True,
    )
    return [_backup_metadata_from_file(path) for path in backups[: max(1, min(limit, 100))]]


def _cleanup_old_backups(protected_names: set[str] | None = None) -> list[str]:
    if BACKUP_KEEP <= 0 or not BACKUP_DIR.exists():
        return []
    protected_names = protected_names or set()
    backups = sorted(
        BACKUP_DIR.glob("openirn-*.sqlite3"),
        key=lambda item: item.stat().st_mtime,
        reverse=True,
    )
    removed: list[str] = []
    for old in backups[BACKUP_KEEP:]:
        if old.name in protected_names:
            continue
        for companion in [old, old.with_suffix(old.suffix + ".sha256"), old.with_suffix(old.suffix + ".json")]:
            if companion.exists():
                companion.unlink()
        removed.append(old.name)
    return removed


def _create_sqlite_backup(
    triggered_by_user_id: str | None = None,
    protected_names: set[str] | None = None,
) -> dict[str, Any]:
    if not DB_PATH.exists():
        raise HTTPException(status_code=503, detail="OpenIRN SQLite database does not exist yet")

    integrity = _sqlite_integrity_check(DB_PATH)
    if integrity != "ok":
        raise HTTPException(status_code=500, detail=f"SQLite integrity_check failed before backup: {integrity}")

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = _utc_now().strftime("%Y%m%dT%H%M%SZ")
    backup_path = BACKUP_DIR / f"openirn-{stamp}.sqlite3"
    suffix = 1
    while backup_path.exists():
        backup_path = BACKUP_DIR / f"openirn-{stamp}-{suffix}.sqlite3"
        suffix += 1

    with sqlite3.connect(DB_PATH) as con:
        con.execute("pragma busy_timeout = 10000")
        con.execute(f"vacuum main into {_canonical_json(str(backup_path))}")

    backup_integrity = _sqlite_integrity_check(backup_path)
    if backup_integrity != "ok":
        raise HTTPException(status_code=500, detail=f"SQLite integrity_check failed for produced backup: {backup_integrity}")

    digest = _file_sha256(backup_path)
    backup_path.with_suffix(backup_path.suffix + ".sha256").write_text(
        f"{digest}  {backup_path.name}\n",
        encoding="utf-8",
    )

    counts: dict[str, int | None] = {}
    with sqlite3.connect(backup_path) as con:
        con.row_factory = sqlite3.Row
        counts = _table_counts(con)

    metadata = {
        "type": "openirn.sqliteBackup",
        "createdAt": _utc_now().isoformat(),
        "sourceDb": str(DB_PATH),
        "backupDb": str(backup_path),
        "triggeredByUserId": triggered_by_user_id or "",
        "sha256": digest,
        "sizeBytes": backup_path.stat().st_size,
        "integrityCheck": backup_integrity,
        "counts": counts,
    }
    backup_path.with_suffix(backup_path.suffix + ".json").write_text(
        _pretty_json(metadata) + "\n",
        encoding="utf-8",
    )
    removed = _cleanup_old_backups(protected_names=protected_names)
    return {**metadata, "name": backup_path.name, "removedOldBackups": removed}


def _backup_path_from_name(backup_name: str) -> Path:
    raw_name = str(backup_name or "").strip()
    safe_name = Path(raw_name).name
    if raw_name != safe_name or not safe_name.startswith("openirn-") or not safe_name.endswith(".sqlite3"):
        raise HTTPException(status_code=400, detail="Invalid backup name")

    backup_dir = BACKUP_DIR.resolve()
    backup_path = (BACKUP_DIR / safe_name).resolve()
    try:
        backup_path.relative_to(backup_dir)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid backup path") from exc

    if not backup_path.exists() or not backup_path.is_file():
        raise HTTPException(status_code=404, detail="Backup not found")
    return backup_path


def _verify_backup_file(backup_path: Path) -> str:
    integrity = _sqlite_integrity_check(backup_path)
    if integrity != "ok":
        raise HTTPException(status_code=500, detail=f"SQLite integrity_check failed for backup: {integrity}")

    digest = _file_sha256(backup_path)
    sha_path = backup_path.with_suffix(backup_path.suffix + ".sha256")
    if sha_path.exists():
        expected_parts = sha_path.read_text(encoding="utf-8").split()
        expected = expected_parts[0].strip() if expected_parts else ""
        if expected and not hmac.compare_digest(digest, expected):
            raise HTTPException(status_code=500, detail="Backup SHA-256 checksum mismatch")
    return digest


def _restore_sqlite_backup(backup_name: str, triggered_by_user_id: str | None = None) -> dict[str, Any]:
    backup_path = _backup_path_from_name(backup_name)
    digest = _verify_backup_file(backup_path)

    safety_backup = _create_sqlite_backup(
        triggered_by_user_id=triggered_by_user_id,
        protected_names={backup_path.name},
    )

    try:
        with sqlite3.connect(backup_path) as source, sqlite3.connect(DB_PATH) as target:
            source.execute("pragma busy_timeout = 10000")
            target.execute("pragma busy_timeout = 10000")
            target.execute("pragma foreign_keys = OFF")
            source.backup(target)
            target.execute("pragma wal_checkpoint(truncate)")
    except sqlite3.Error as exc:
        raise HTTPException(status_code=500, detail=f"SQLite restore failed: {exc}") from exc

    restored_integrity = _sqlite_integrity_check(DB_PATH)
    if restored_integrity != "ok":
        raise HTTPException(status_code=500, detail=f"SQLite integrity_check failed after restore: {restored_integrity}")

    with _db() as con:
        counts = _table_counts(con)

    return {
        "status": "ok",
        "type": "openirn.sqliteBackupRestored",
        "restoredAt": _utc_now().isoformat(),
        "backup": _backup_metadata_from_file(backup_path),
        "backupSha256": digest,
        "preRestoreBackup": safety_backup,
        "triggeredByUserId": triggered_by_user_id or "",
        "integrityCheck": restored_integrity,
        "counts": counts,
    }


def _delete_sqlite_backup(backup_name: str) -> dict[str, Any]:
    backup_path = _backup_path_from_name(backup_name)
    deleted: list[str] = []
    for companion in [
        backup_path,
        backup_path.with_suffix(backup_path.suffix + ".sha256"),
        backup_path.with_suffix(backup_path.suffix + ".json"),
    ]:
        if companion.exists():
            companion.unlink()
            deleted.append(companion.name)
    return {
        "status": "ok",
        "type": "openirn.sqliteBackupDeleted",
        "deletedAt": _utc_now().isoformat(),
        "backupName": backup_path.name,
        "deletedFiles": deleted,
    }


def _maintenance_status(limit: int = 10) -> dict[str, Any]:
    with _db() as con:
        counts = _table_counts(con)

    wal_path = Path(str(DB_PATH) + "-wal")
    shm_path = Path(str(DB_PATH) + "-shm")
    backups = _list_backups(limit=limit)
    return {
        "status": "ok",
        "type": "openirn.maintenanceStatus",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "serverTime": _utc_now().isoformat(),
        "database": {
            "path": str(DB_PATH),
            "exists": DB_PATH.exists(),
            "sizeBytes": DB_PATH.stat().st_size if DB_PATH.exists() else 0,
            "walSizeBytes": wal_path.stat().st_size if wal_path.exists() else 0,
            "shmSizeBytes": shm_path.stat().st_size if shm_path.exists() else 0,
            "integrityCheck": _sqlite_integrity_check(DB_PATH),
            "counts": counts,
        },
        "backup": {
            "directory": str(BACKUP_DIR),
            "keep": BACKUP_KEEP,
            "count": len(list(BACKUP_DIR.glob("openirn-*.sqlite3"))) if BACKUP_DIR.exists() else 0,
            "latest": backups[0] if backups else None,
            "backups": backups,
        },
    }


@app.get("/devices")
def devices(
    request: Request,
    tenantId: str = Query(default="default", min_length=1, max_length=80),
) -> dict[str, Any]:
    _require_api_token(request)
    tenant_id = _safe_segment(tenantId, "default")
    with _db() as con:
        _ensure_tenant(con, tenant_id)
        devices_list = _list_devices(con, tenant_id)
        con.commit()
    return {
        "status": "ok",
        "type": "openirn.devices",
        "tenantId": tenant_id,
        "deviceCount": len(devices_list),
        "devices": devices_list,
        "serverTime": _utc_now().isoformat(),
    }


@app.post("/devices/enrollment")
async def devices_enrollment(request: Request) -> dict[str, Any]:
    _require_api_token(request)
    try:
        payload = await request.json()
    except json.JSONDecodeError:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    tenant_id = _safe_segment(payload.get("tenantId"), "default")
    created_by_user_id = str(payload.get("createdByUserId") or "").strip()[:120]
    label = str(payload.get("label") or "").strip()[:120]
    allowed_expiration_minutes = {5, 10, 15}
    try:
        expires_in_minutes = int(payload.get("expiresInMinutes") or 10)
    except (TypeError, ValueError):
        expires_in_minutes = 10
    if expires_in_minutes not in allowed_expiration_minutes:
        expires_in_minutes = 10

    raw_code = _new_enrollment_code()
    display_code = _format_enrollment_code(raw_code)
    normalized_code = _normalize_enrollment_code(raw_code)
    enrollment_id = f"enrollment_{uuid.uuid4().hex}"
    now = _utc_now()
    expires_at = now + timedelta(minutes=expires_in_minutes)

    with _db() as con:
        _ensure_tenant(con, tenant_id)
        con.execute(
            """
            INSERT INTO device_enrollment_codes(
                tenant_id, enrollment_id, code_hash, created_by_user_id, label,
                expires_at, consumed_at, consumed_by_device_id, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, ?)
            """,
            (
                tenant_id,
                enrollment_id,
                _enrollment_code_hash(tenant_id, normalized_code),
                created_by_user_id,
                label,
                expires_at.isoformat(),
                now.isoformat(),
            ),
        )
        _record_device_audit(
            con,
            tenant_id,
            "enrollment.created",
            payload={
                "enrollmentId": enrollment_id,
                "createdByUserId": created_by_user_id,
                "label": label,
                "expiresAt": expires_at.isoformat(),
            },
        )
        con.commit()

    qr_payload = {
        "type": "openirn.deviceEnrollment",
        "tenantId": tenant_id,
        "code": display_code,
        "enrollmentId": enrollment_id,
        "expiresAt": expires_at.isoformat(),
    }
    return {
        "status": "ok",
        "type": "openirn.deviceEnrollment",
        "tenantId": tenant_id,
        "enrollmentId": enrollment_id,
        "code": display_code,
        "expiresAt": expires_at.isoformat(),
        "expiresInMinutes": expires_in_minutes,
        "qrPayload": qr_payload,
        "qrPayloadText": _canonical_json(qr_payload),
        "serverTime": _utc_now().isoformat(),
    }


@app.post("/devices/enrollment/consume")
async def devices_enrollment_consume(request: Request) -> dict[str, Any]:
    try:
        payload = await request.json()
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail="Invalid JSON payload") from exc
    if not isinstance(payload, dict):
        raise HTTPException(status_code=400, detail="Invalid JSON payload")

    tenant_id = _safe_segment(payload.get("tenantId"), "default")
    code = _normalize_enrollment_code(payload.get("code"))
    if len(code) < 8:
        raise HTTPException(status_code=400, detail="Invalid enrollment code")

    device_name = str(payload.get("deviceName") or "").strip()[:120] or "Terminal OpenIRN"
    platform = str(payload.get("platform") or "").strip()[:80]
    now = _utc_now()
    code_hashes = _enrollment_code_hash_candidates(tenant_id, code)
    placeholders = ", ".join("?" for _ in code_hashes)

    with _db() as con:
        _ensure_tenant(con, tenant_id)
        enrollment = con.execute(
            f"""
            SELECT tenant_id, enrollment_id, created_by_user_id, label,
                   expires_at, consumed_at, consumed_by_device_id, created_at
            FROM device_enrollment_codes
            WHERE tenant_id = ? AND code_hash IN ({placeholders})
            """,
            (tenant_id, *code_hashes),
        ).fetchone()
        if enrollment is None:
            raise HTTPException(status_code=404, detail="Unknown enrollment code")
        if enrollment["consumed_at"]:
            raise HTTPException(status_code=409, detail="Enrollment code has already been consumed")
        if _parse_datetime(enrollment["expires_at"]) < now:
            raise HTTPException(status_code=410, detail="Enrollment code has expired")

        device, token = _create_device(
            con,
            tenant_id,
            name=device_name,
            platform=platform,
            invited_by_user_id=str(enrollment["created_by_user_id"] or ""),
            enrollment_id=str(enrollment["enrollment_id"] or ""),
        )
        con.execute(
            """
            UPDATE device_enrollment_codes
            SET consumed_at = ?, consumed_by_device_id = ?
            WHERE tenant_id = ? AND enrollment_id = ?
            """,
            (now.isoformat(), device["deviceId"], tenant_id, enrollment["enrollment_id"]),
        )
        _record_device_audit(
            con,
            tenant_id,
            "enrollment.consumed",
            device_id=device["deviceId"],
            payload={
                "enrollmentId": enrollment["enrollment_id"],
                "deviceName": device_name,
                "platform": platform,
            },
        )
        con.commit()

    return {
        "status": "ok",
        "type": "openirn.deviceEnrollmentConsumed",
        "tenantId": tenant_id,
        "apiToken": "",
        "device": device,
        "serverTime": _utc_now().isoformat(),
    }


@app.post("/devices/{device_id}/rename")
async def device_rename(device_id: str, request: Request) -> dict[str, Any]:
    _require_api_token(request)
    try:
        payload = await request.json()
    except json.JSONDecodeError:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    tenant_id = _safe_segment(payload.get("tenantId"), "default")
    name = str(payload.get("name") or "").strip()[:120]
    if not name:
        raise HTTPException(status_code=400, detail="Missing device name")

    with _db() as con:
        row = con.execute(
            "SELECT 1 FROM authorized_devices WHERE tenant_id = ? AND device_id = ?",
            (tenant_id, device_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Device not found")
        con.execute(
            "UPDATE authorized_devices SET name = ? WHERE tenant_id = ? AND device_id = ?",
            (name, tenant_id, device_id),
        )
        _record_device_audit(
            con,
            tenant_id,
            "device.renamed",
            device_id=device_id,
            payload={"name": name},
        )
        con.commit()
        devices_list = _list_devices(con, tenant_id)
    return {
        "status": "ok",
        "type": "openirn.deviceRenamed",
        "tenantId": tenant_id,
        "deviceId": device_id,
        "devices": devices_list,
        "serverTime": _utc_now().isoformat(),
    }


@app.delete("/devices/{device_id}")
def device_revoke(
    device_id: str,
    request: Request,
    tenantId: str = Query(default="default", min_length=1, max_length=80),
) -> dict[str, Any]:
    _require_api_token(request)
    tenant_id = _safe_segment(tenantId, "default")
    now = _utc_now().isoformat()
    with _db() as con:
        row = con.execute(
            "SELECT status FROM authorized_devices WHERE tenant_id = ? AND device_id = ?",
            (tenant_id, device_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Device not found")
        con.execute(
            """
            UPDATE authorized_devices
            SET status = 'revoked', revoked_at = ?
            WHERE tenant_id = ? AND device_id = ?
            """,
            (now, tenant_id, device_id),
        )
        _record_device_audit(
            con,
            tenant_id,
            "device.revoked",
            device_id=device_id,
            payload={},
        )
        con.commit()
        devices_list = _list_devices(con, tenant_id)
    return {
        "status": "ok",
        "type": "openirn.deviceRevoked",
        "tenantId": tenant_id,
        "deviceId": device_id,
        "devices": devices_list,
        "serverTime": _utc_now().isoformat(),
    }


@app.get("/referential/official/status")
def official_referential_status(
    request: Request,
    tenantId: str = Query(default="default", min_length=1, max_length=80),
) -> dict[str, Any]:
    _require_api_token(request)
    tenant_id = _safe_segment(tenantId, "default")
    remote = _official_remote_latest()
    with _db() as con:
        _ensure_tenant(con, tenant_id)
        current_row = _load_current_official_referential(con, tenant_id)
        current = _official_referential_summary_from_row(current_row)
        con.commit()

    update_available = current is None or str(current.get("sourceBlobId") or "") != str(remote.get("blobId") or "")
    if current is not None and str(current.get("version") or "") != str(remote.get("version") or ""):
        update_available = True

    return {
        "status": "ok",
        "type": "openirn.officialReferentialStatus",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "source": {
            "provider": "gitlab",
            "projectPath": OFFICIAL_ADRI_PROJECT_PATH,
            "treePath": OFFICIAL_ADRI_TREE_PATH,
            "sourceUrl": OFFICIAL_ADRI_SOURCE_URL,
        },
        "current": current,
        "remote": remote,
        "updateAvailable": update_available,
    }


@app.get("/referential/official/current")
def official_referential_current(
    request: Request,
    tenantId: str = Query(default="default", min_length=1, max_length=80),
) -> dict[str, Any]:
    tenant_id = _safe_segment(tenantId, "default")
    if not _request_has_api_authorization(request):
        _require_active_device(request, tenant_id)
    with _db() as con:
        current_row = _load_current_official_referential(con, tenant_id)
        if current_row is None:
            raise HTTPException(status_code=404, detail="Aucun référentiel officiel n'est installé sur le serveur")
        payload = _parse_json(current_row["payload_json"], {})
    if not isinstance(payload, dict):
        raise HTTPException(status_code=500, detail="Référentiel officiel serveur invalide")
    return {
        "status": "ok",
        "type": "openirn.officialReferentialCurrent",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "referential": payload,
        "summary": _official_referential_summary_from_row(current_row),
    }


@app.post("/referential/official/update")
async def official_referential_update(request: Request) -> dict[str, Any]:
    _require_api_token(request)
    try:
        payload = await request.json()
    except json.JSONDecodeError:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    tenant_id = _safe_segment(payload.get("tenantId"), "default")
    force = payload.get("force") is True
    triggered_by_user_id = str(payload.get("triggeredByUserId") or "").strip()[:120]

    remote = _official_remote_latest()
    with _db() as con:
        _ensure_tenant(con, tenant_id)
        current_row = _load_current_official_referential(con, tenant_id)
        current = _official_referential_summary_from_row(current_row)
        con.commit()

    update_available = current is None or str(current.get("sourceBlobId") or "") != str(remote.get("blobId") or "")
    if current is not None and str(current.get("version") or "") != str(remote.get("version") or ""):
        update_available = True

    if current is not None and not update_available and not force:
        return {
            "status": "up_to_date",
            "type": "openirn.officialReferentialUpdate",
            "application": "OpenIRN API",
            "version": APP_VERSION,
            "tenantId": tenant_id,
            "serverTime": _utc_now().isoformat(),
            "message": "Le référentiel officiel serveur est déjà aligné avec le dernier fichier GitLab détecté.",
            "current": current,
            "remote": remote,
            "updateAvailable": False,
        }

    raw_xlsx = _download_official_adri_xlsx(remote)
    referential = _adri_parse_workbook(raw_xlsx, version=str(remote.get("version") or "unknown"), remote=remote)
    validation = _adri_validation_report(referential)
    if validation.get("status") == "failed":
        raise HTTPException(status_code=422, detail={"message": "Le référentiel téléchargé n'a pas passé la validation OpenIRN", "validation": validation})

    with _db() as con:
        with con:
            _ensure_tenant(con, tenant_id)
            stored = _store_official_referential(con, tenant_id, referential, remote, validation, raw_xlsx)
            con.execute(
                """
                INSERT INTO sync_events(tenant_id, event_type, server_sync_id, campaign_id, device_id, created_at, payload_json)
                VALUES (?, 'official_referential_updated', NULL, NULL, ?, ?, ?)
                """,
                (
                    tenant_id,
                    triggered_by_user_id or "server",
                    _utc_now().isoformat(),
                    _canonical_json({
                        "referentialId": stored["referentialId"],
                        "version": stored["version"],
                        "sourceBlobId": remote.get("blobId") or "",
                        "criterionCount": stored["criterionCount"],
                    }),
                ),
            )
            current_row = _load_current_official_referential(con, tenant_id)
            current = _official_referential_summary_from_row(current_row)

    return {
        "status": "updated",
        "type": "openirn.officialReferentialUpdate",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "message": "Référentiel officiel aDRI téléchargé, validé et installé sur le serveur.",
        "current": current,
        "remote": remote,
        "validation": validation,
        "stored": stored,
        "updateAvailable": False,
    }

@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "storage": "sqlite",
        "database": str(DB_PATH),
        "authRequired": True,
        "authMode": "bearer_token_or_device_token",
        "endpoints": [
            "/health",
            "/auth/verify",
            "/auth/sessions",
            "/security/audit",
            "/users",
            "/users/replace",
            "/users/pin",
            "/devices",
            "/devices/enrollment",
            "/devices/enrollment/consume",
            "/devices/{device_id}/rename",
            "/devices/{device_id}",
            "/referential/official/status",
            "/referential/official/current",
            "/referential/official/update",
            "/sync/push",
            "/sync/status",
            "/sync/pull",
            "/sync/events",
            "/campaigns",
            "/campaigns/revisions",
            "/campaigns/conflicts",
            "/campaigns/revision",
            "/campaigns/restore",
            "/maintenance/status",
            "/maintenance/backup",
            "/maintenance/backups/{backup_name}/restore",
            "/maintenance/backups/{backup_name}",
        ],
        "timestamp": _utc_now().isoformat(),
    }


@app.post("/sync/push")
async def sync_push(request: Request) -> dict[str, Any]:
    _require_api_token(request)

    try:
        payload = await request.json()
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail="Invalid JSON payload") from exc

    if not isinstance(payload, dict):
        raise HTTPException(status_code=400, detail="Payload must be a JSON object")
    if payload.get("type") != "openirn.syncPush":
        raise HTTPException(status_code=400, detail="Unsupported payload type")

    sync_context = payload.get("sync")
    if not isinstance(sync_context, dict):
        raise HTTPException(status_code=400, detail="Missing sync context")

    tenant_id = _safe_segment(sync_context.get("tenantId"), "default")
    device_id = _safe_segment(sync_context.get("deviceId"), "unknown-device")
    campaigns = _extract_campaigns(payload)

    received_at = _utc_now().isoformat()
    server_sync_id = f"sync_{_utc_now().strftime('%Y%m%dT%H%M%SZ')}_{uuid.uuid4().hex[:12]}"
    payload_sha256 = _json_sha256(payload)
    envelope = {
        "serverSyncId": server_sync_id,
        "receivedAt": received_at,
        "tenantId": tenant_id,
        "deviceId": device_id,
        "payloadSha256": payload_sha256,
        "payload": payload,
    }

    with _db() as con:
        with con:
            _ensure_tenant(con, tenant_id)
            con.execute(
                """
                INSERT INTO sync_snapshots(
                    tenant_id, server_sync_id, device_id, received_at,
                    payload_sha256, campaign_count, payload_json, envelope_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    tenant_id,
                    server_sync_id,
                    device_id,
                    received_at,
                    payload_sha256,
                    len(campaigns),
                    _canonical_json(payload),
                    _canonical_json(envelope),
                ),
            )
            central_user_count = _merge_central_users(con, tenant_id, payload.get("users"))
            revision_stats = _record_campaign_revisions(con, tenant_id, server_sync_id, device_id, received_at, payload)
            con.execute(
                """
                INSERT INTO sync_events(
                    tenant_id, event_type, server_sync_id, device_id,
                    created_at, payload_json
                ) VALUES (?, 'snapshot_accepted', ?, ?, ?, ?)
                """,
                (
                    tenant_id,
                    server_sync_id,
                    device_id,
                    _utc_now().isoformat(),
                    _canonical_json(
                        {
                            "serverSyncId": server_sync_id,
                            "campaignCount": len(campaigns),
                            "revisionCount": revision_stats["revisionCount"],
                            "conflictCount": revision_stats["conflictCount"],
                            "deletedCount": revision_stats.get("deletedCount", 0),
                        }
                    ),
                ),
            )

    return {
        "status": "accepted",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "storage": "sqlite",
        "serverSyncId": server_sync_id,
        "receivedAt": received_at,
        "tenantId": tenant_id,
        "deviceId": device_id,
        "payloadSha256": payload_sha256,
        "stored": True,
        "campaignCount": len(campaigns),
        "centralUserCount": central_user_count,
        "campaignRevisionCount": revision_stats["revisionCount"],
        "conflictCount": revision_stats["conflictCount"],
        "deletedCount": revision_stats.get("deletedCount", 0),
        "conflictPolicy": "last_write_wins",
    }


@app.post("/auth/verify")
async def auth_verify(request: Request) -> dict[str, Any]:
    try:
        payload = await request.json()
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail="Invalid JSON payload") from exc

    if not isinstance(payload, dict):
        raise HTTPException(status_code=400, detail="Payload must be a JSON object")

    tenant_id = _safe_segment(payload.get("tenantId"), "default")
    user_id = str(payload.get("userId") or "").strip()
    pin = str(payload.get("pin") or "")
    device_id = _require_active_device(request, tenant_id, payload)
    ip_address = _request_client_ip(request)
    if not user_id:
        raise HTTPException(status_code=400, detail="Missing userId")
    if not pin.strip():
        raise HTTPException(status_code=400, detail="Missing PIN")

    with _db() as con:
        _ensure_tenant(con, tenant_id)
        _enforce_auth_rate_limit(
            con,
            tenant_id,
            device_id=device_id,
            user_id=user_id,
            ip_address=ip_address,
        )
        users = _load_central_users(con, tenant_id)
        _ensure_user_credentials(con, tenant_id, users)
        con.commit()
        user = next((candidate for candidate in users if candidate.get("id") == user_id), None)
        if user is None:
            _record_auth_attempt(
                con,
                tenant_id,
                device_id=device_id,
                user_id=user_id,
                ip_address=ip_address,
                successful=False,
                reason="unknown_user",
            )
            _record_device_audit(
                con,
                tenant_id,
                "auth.failed",
                device_id=device_id,
                payload={"userId": user_id, "reason": "unknown_user", "ipAddress": ip_address},
            )
            con.commit()
            raise HTTPException(status_code=404, detail="Unknown user")
        if user.get("active") is not True:
            _record_auth_attempt(
                con,
                tenant_id,
                device_id=device_id,
                user_id=user_id,
                ip_address=ip_address,
                successful=False,
                reason="inactive_user",
            )
            _record_device_audit(
                con,
                tenant_id,
                "auth.failed",
                device_id=device_id,
                payload={"userId": user_id, "reason": "inactive_user", "ipAddress": ip_address},
            )
            con.commit()
            raise HTTPException(status_code=403, detail="Inactive user")
        accepted, requires_change = _verify_user_pin(con, tenant_id, user_id, pin)
        if not accepted:
            _record_auth_attempt(
                con,
                tenant_id,
                device_id=device_id,
                user_id=user_id,
                ip_address=ip_address,
                successful=False,
                reason="invalid_pin",
            )
            _record_device_audit(
                con,
                tenant_id,
                "auth.failed",
                device_id=device_id,
                payload={"userId": user_id, "reason": "invalid_pin", "ipAddress": ip_address},
            )
            con.commit()
            raise HTTPException(status_code=403, detail="Invalid user code")
        session_id, session_token, expires_at = _create_api_session(
            con,
            tenant_id,
            device_id,
            user_id,
        )
        _record_auth_attempt(
            con,
            tenant_id,
            device_id=device_id,
            user_id=user_id,
            ip_address=ip_address,
            successful=True,
            reason="accepted",
        )
        _record_device_audit(
            con,
            tenant_id,
            "session.created",
            device_id=device_id,
            payload={"userId": user_id, "sessionId": session_id, "ipAddress": ip_address},
        )
        con.commit()

    return {
        "status": "accepted",
        "type": "openirn.userAuthentication",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "userId": user_id,
        "mustChangePin": requires_change,
        "user": user,
        "sessionId": session_id,
        "apiToken": session_token,
        "expiresAt": expires_at.isoformat(),
    }



def _session_row_to_payload(row: sqlite3.Row, *, current_token_hash: str = '') -> dict[str, Any]:
    now = _utc_now()
    expires_at = _parse_datetime(row["expires_at"])
    revoked_at_raw = row["revoked_at"]
    revoked_at = _parse_datetime(revoked_at_raw) if revoked_at_raw else None
    if revoked_at is not None:
        status = "revoked"
    elif expires_at < now:
        status = "expired"
    else:
        status = "active"

    user_payload = _parse_json(row["user_payload_json"], {})
    first_name = str(user_payload.get("firstName") or user_payload.get("first_name") or "").strip()
    last_name = str(user_payload.get("lastName") or user_payload.get("last_name") or "").strip()
    full_name = " ".join(part for part in (first_name, last_name) if part).strip()
    email = str(user_payload.get("email") or "").strip()
    role = str(user_payload.get("role") or row["user_role"] or "").strip()

    return {
        "sessionId": row["session_id"],
        "tenantId": row["tenant_id"],
        "deviceId": row["device_id"],
        "deviceName": row["device_name"] or row["device_id"],
        "devicePlatform": row["device_platform"] or "",
        "userId": row["user_id"],
        "userDisplayName": full_name or email or row["user_id"],
        "userEmail": email,
        "userRole": role,
        "status": status,
        "isCurrentSession": bool(current_token_hash and hmac.compare_digest(row["token_hash"], current_token_hash)),
        "createdAt": row["created_at"],
        "expiresAt": row["expires_at"],
        "lastSeenAt": row["last_seen_at"],
        "revokedAt": row["revoked_at"],
    }



@app.get("/security/audit")
def security_audit(
    request: Request,
    tenantId: str = Query(default="default", min_length=1, max_length=80),
    limit: int = Query(default=100, ge=25, le=500),
    includeAuthAttempts: bool = Query(default=True),
    includeDeviceAudit: bool = Query(default=True),
) -> dict[str, Any]:
    tenant_id = _safe_segment(tenantId, "default")
    _require_api_token(request)
    safe_limit = max(25, min(int(limit), 500))
    events: list[dict[str, Any]] = []

    with _db() as con:
        _ensure_tenant(con, tenant_id)
        if includeDeviceAudit:
            audit_rows = con.execute(
                """
                SELECT id, tenant_id, device_id, event_type, created_at, payload_json
                FROM device_audit_log
                WHERE tenant_id = ?
                ORDER BY created_at DESC, id DESC
                LIMIT ?
                """,
                (tenant_id, safe_limit),
            ).fetchall()
            for row in audit_rows:
                events.append(
                    {
                        "source": "deviceAudit",
                        "eventId": f"audit-{row['id']}",
                        "tenantId": row["tenant_id"],
                        "deviceId": row["device_id"] or "",
                        "eventType": row["event_type"] or "",
                        "createdAt": row["created_at"],
                        "payload": _parse_json(row["payload_json"], {}),
                    }
                )

        if includeAuthAttempts:
            attempt_rows = con.execute(
                """
                SELECT
                    tenant_id, attempt_id, device_id, user_id, ip_address,
                    successful, reason, created_at
                FROM auth_attempts
                WHERE tenant_id = ?
                ORDER BY created_at DESC, attempt_id DESC
                LIMIT ?
                """,
                (tenant_id, safe_limit),
            ).fetchall()
            for row in attempt_rows:
                events.append(
                    {
                        "source": "authAttempt",
                        "eventId": row["attempt_id"],
                        "tenantId": row["tenant_id"],
                        "deviceId": row["device_id"] or "",
                        "eventType": "auth.success" if bool(row["successful"]) else "auth.failed",
                        "createdAt": row["created_at"],
                        "userId": row["user_id"] or "",
                        "ipAddress": row["ip_address"] or "",
                        "successful": bool(row["successful"]),
                        "reason": row["reason"] or "",
                        "payload": {
                            "reason": row["reason"] or "",
                            "successful": bool(row["successful"]),
                        },
                    }
                )

    events.sort(key=lambda item: str(item.get("createdAt") or ""), reverse=True)
    events = events[:safe_limit]
    auth_count = sum(1 for event in events if event.get("source") == "authAttempt")
    device_count = sum(1 for event in events if event.get("source") == "deviceAudit")
    failure_count = sum(1 for event in events if event.get("successful") is False)

    return {
        "status": "ok",
        "type": "openirn.securityAudit",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "eventCount": len(events),
        "authAttemptCount": auth_count,
        "deviceAuditCount": device_count,
        "failureCount": failure_count,
        "events": events,
    }


@app.get("/auth/sessions")
def auth_sessions(
    request: Request,
    tenantId: str = Query(default="default", min_length=1, max_length=80),
    includeInactive: bool = Query(default=True),
) -> dict[str, Any]:
    tenant_id = _safe_segment(tenantId, "default")
    _require_api_token(request)
    provided_token = _extract_bearer_token(request)
    current_token_hash = _secret_hash(provided_token) if provided_token.startswith("ost_") else ""
    now_iso = _utc_now().isoformat()

    where_inactive = "" if includeInactive else "AND s.revoked_at IS NULL AND s.expires_at >= ?"
    params: tuple[Any, ...]
    if includeInactive:
        params = (tenant_id,)
    else:
        params = (tenant_id, now_iso)

    with _db() as con:
        _ensure_tenant(con, tenant_id)
        rows = con.execute(
            f"""
            SELECT
                s.tenant_id,
                s.session_id,
                s.token_hash,
                s.device_id,
                s.user_id,
                s.created_at,
                s.expires_at,
                s.last_seen_at,
                s.revoked_at,
                d.name AS device_name,
                d.platform AS device_platform,
                u.role AS user_role,
                u.payload_json AS user_payload_json
            FROM api_sessions s
            LEFT JOIN authorized_devices d
              ON d.tenant_id = s.tenant_id AND d.device_id = s.device_id
            LEFT JOIN users u
              ON u.tenant_id = s.tenant_id AND u.user_id = s.user_id
            WHERE s.tenant_id = ?
              {where_inactive}
            ORDER BY
              CASE WHEN s.revoked_at IS NULL AND s.expires_at >= ? THEN 0 ELSE 1 END,
              s.last_seen_at DESC,
              s.created_at DESC
            LIMIT 250
            """,
            params + (now_iso,),
        ).fetchall()

    sessions = [
        _session_row_to_payload(row, current_token_hash=current_token_hash)
        for row in rows
    ]
    active_count = sum(1 for session in sessions if session["status"] == "active")
    expired_count = sum(1 for session in sessions if session["status"] == "expired")
    revoked_count = sum(1 for session in sessions if session["status"] == "revoked")

    return {
        "status": "ok",
        "type": "openirn.apiSessions",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "sessionCount": len(sessions),
        "activeCount": active_count,
        "expiredCount": expired_count,
        "revokedCount": revoked_count,
        "sessions": sessions,
    }


@app.delete("/auth/sessions/{session_id}")
def revoke_auth_session(
    session_id: str,
    request: Request,
    tenantId: str = Query(default="default", min_length=1, max_length=80),
) -> dict[str, Any]:
    tenant_id = _safe_segment(tenantId, "default")
    safe_session_id = str(session_id or "").strip()[:160]
    if not safe_session_id:
        raise HTTPException(status_code=400, detail="Missing session id")
    _require_api_token(request)
    provided_token = _extract_bearer_token(request)
    current_token_hash = _secret_hash(provided_token) if provided_token.startswith("ost_") else ""
    now = _utc_now()

    with _db() as con:
        _ensure_tenant(con, tenant_id)
        row = con.execute(
            """
            SELECT session_id, token_hash, device_id, user_id, revoked_at
            FROM api_sessions
            WHERE tenant_id = ? AND session_id = ?
            """,
            (tenant_id, safe_session_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Session inconnue")
        if current_token_hash and hmac.compare_digest(row["token_hash"], current_token_hash):
            raise HTTPException(status_code=400, detail="La session courante ne peut pas être révoquée depuis cette action")
        if row["revoked_at"] is None:
            con.execute(
                """
                UPDATE api_sessions
                SET revoked_at = ?
                WHERE tenant_id = ? AND session_id = ?
                """,
                (now.isoformat(), tenant_id, safe_session_id),
            )
            _record_device_audit(
                con,
                tenant_id,
                "session.revoked",
                device_id=row["device_id"],
                payload={"sessionId": safe_session_id, "userId": row["user_id"]},
            )
            con.commit()

    return {
        "status": "ok",
        "type": "openirn.apiSessionRevoked",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "sessionId": safe_session_id,
        "message": "Session révoquée.",
    }


@app.get("/users")
def users(request: Request, tenantId: str = Query(default="default", min_length=1, max_length=80)) -> dict[str, Any]:
    tenant_id = _safe_segment(tenantId, "default")
    if not _request_has_api_authorization(request):
        _require_active_device(request, tenant_id)

    with _db() as con:
        _ensure_tenant(con, tenant_id)
        central_users = _load_central_users(con, tenant_id)
        _ensure_user_credentials(con, tenant_id, central_users)
        con.commit()

    return {
        "status": "ok",
        "type": "openirn.centralUsers",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "userCount": len(central_users),
        "users": central_users,
    }


@app.post("/users/replace")
async def users_replace(request: Request) -> dict[str, Any]:
    _require_api_token(request)

    try:
        payload = await request.json()
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail="Invalid JSON payload") from exc

    if not isinstance(payload, dict):
        raise HTTPException(status_code=400, detail="Payload must be a JSON object")

    tenant_id = _safe_segment(payload.get("tenantId"), "default")
    raw_users = payload.get("users")
    if not isinstance(raw_users, list):
        raise HTTPException(status_code=400, detail="Missing users array")

    users_to_save = [user for raw_user in raw_users if (user := _sanitize_user(raw_user))]
    user_ids = {user["id"] for user in users_to_save}
    with _db() as con:
        with con:
            _ensure_tenant(con, tenant_id)
            for user in users_to_save:
                _save_user(con, tenant_id, user)
            if user_ids:
                placeholders = ",".join("?" for _ in user_ids)
                con.execute(
                    f"DELETE FROM users WHERE tenant_id = ? AND user_id NOT IN ({placeholders})",
                    (tenant_id, *sorted(user_ids)),
                )
            else:
                con.execute("DELETE FROM users WHERE tenant_id = ?", (tenant_id,))
            _ensure_user_credentials(con, tenant_id, users_to_save)

    return {
        "status": "accepted",
        "type": "openirn.centralUsersReplace",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "userCount": len(users_to_save),
    }


@app.post("/users/pin")
async def users_pin(request: Request) -> dict[str, Any]:
    _require_api_token(request)

    try:
        payload = await request.json()
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail="Invalid JSON payload") from exc

    if not isinstance(payload, dict):
        raise HTTPException(status_code=400, detail="Payload must be a JSON object")

    tenant_id = _safe_segment(payload.get("tenantId"), "default")
    user_id = str(payload.get("userId") or "").strip()
    pin = str(payload.get("pin") or payload.get("newPin") or "").strip()
    if not user_id:
        raise HTTPException(status_code=400, detail="Missing userId")

    with _db() as con:
        with con:
            _ensure_tenant(con, tenant_id)
            _set_user_pin(con, tenant_id, user_id, pin, requires_change=False)

    return {
        "status": "accepted",
        "type": "openirn.userPinUpdate",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "userId": user_id,
    }


@app.get("/sync/status")
def sync_status(request: Request, tenantId: str = Query(default="default", min_length=1, max_length=80)) -> dict[str, Any]:
    tenant_id = _safe_segment(tenantId, "default")
    _require_sync_read_access(request, tenant_id)

    with _db() as con:
        latest_row = con.execute(
            """
            SELECT tenant_id, server_sync_id, device_id, received_at,
                   payload_sha256, campaign_count, payload_json
            FROM sync_snapshots
            WHERE tenant_id = ?
            ORDER BY received_at DESC, server_sync_id DESC
            LIMIT 1
            """,
            (tenant_id,),
        ).fetchone()
        snapshot_count = int(
            con.execute("SELECT COUNT(*) FROM sync_snapshots WHERE tenant_id = ?", (tenant_id,)).fetchone()[0]
        )
        device_count = int(
            con.execute("SELECT COUNT(DISTINCT device_id) FROM sync_snapshots WHERE tenant_id = ?", (tenant_id,)).fetchone()[0]
        )
        campaign_count = int(
            con.execute("SELECT COALESCE(SUM(campaign_count), 0) FROM sync_snapshots WHERE tenant_id = ?", (tenant_id,)).fetchone()[0]
        )
        current_campaign_count = int(
            con.execute("SELECT COUNT(*) FROM campaign_states WHERE tenant_id = ?", (tenant_id,)).fetchone()[0]
        )
        conflict_count = int(
            con.execute(
                "SELECT COUNT(*) FROM campaign_revisions WHERE tenant_id = ? AND conflict_detected = 1",
                (tenant_id,),
            ).fetchone()[0]
        )

    return {
        "status": "ok",
        "type": "openirn.syncStatus",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "storage": "sqlite",
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "snapshotCount": snapshot_count,
        "deviceCount": device_count,
        "campaignCount": campaign_count,
        "currentCampaignCount": current_campaign_count,
        "conflictCount": conflict_count,
        "conflictPolicy": "last_write_wins",
        "latestSnapshot": _snapshot_summary_from_row(latest_row),
    }


@app.get("/sync/pull")
def sync_pull(
    request: Request,
    tenantId: str = Query(default="default", min_length=1, max_length=80),
    limit: int = Query(default=10, ge=1, le=50),
) -> dict[str, Any]:
    tenant_id = _safe_segment(tenantId, "default")
    _require_sync_read_access(request, tenant_id)

    with _db() as con:
        rows = con.execute(
            """
            SELECT tenant_id, server_sync_id, device_id, received_at,
                   payload_sha256, campaign_count, payload_json
            FROM sync_snapshots
            WHERE tenant_id = ?
            ORDER BY received_at DESC, server_sync_id DESC
            LIMIT ?
            """,
            (tenant_id, limit),
        ).fetchall()
        available_snapshot_count = int(
            con.execute("SELECT COUNT(*) FROM sync_snapshots WHERE tenant_id = ?", (tenant_id,)).fetchone()[0]
        )

    snapshots = [_public_snapshot_from_row(row) for row in rows]
    return {
        "status": "ok",
        "type": "openirn.syncPull",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "storage": "sqlite",
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "snapshotCount": len(snapshots),
        "availableSnapshotCount": available_snapshot_count,
        "limit": limit,
        "snapshots": snapshots,
    }


@app.get("/campaigns")
def campaigns(
    request: Request,
    tenantId: str = Query(default="default", min_length=1, max_length=80),
    limit: int = Query(default=100, ge=1, le=500),
) -> dict[str, Any]:
    tenant_id = _safe_segment(tenantId, "default")
    _require_sync_read_access(request, tenant_id)

    with _db() as con:
        rows = con.execute(
            """
            SELECT tenant_id, campaign_id, server_revision, server_sync_id,
                   device_id, updated_at, received_at, payload_sha256,
                   payload_json, conflict_policy
            FROM campaign_states
            WHERE tenant_id = ?
            ORDER BY received_at DESC, updated_at DESC, campaign_id ASC
            LIMIT ?
            """,
            (tenant_id, limit),
        ).fetchall()
        revision_count = int(
            con.execute(
                "SELECT COUNT(*) FROM campaign_revisions WHERE tenant_id = ?",
                (tenant_id,),
            ).fetchone()[0]
        )
        conflict_count = int(
            con.execute(
                "SELECT COUNT(*) FROM campaign_revisions WHERE tenant_id = ? AND conflict_detected = 1",
                (tenant_id,),
            ).fetchone()[0]
        )

    items = [_public_campaign_state_from_row(row) for row in rows]
    return {
        "status": "ok",
        "type": "openirn.campaignStates",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "storage": "sqlite",
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "campaignCount": len(items),
        "revisionCount": revision_count,
        "conflictCount": conflict_count,
        "campaigns": items,
    }


@app.get("/campaigns/revisions")
def campaign_revisions(
    request: Request,
    tenantId: str = Query(default="default", min_length=1, max_length=80),
    campaignId: str = Query(min_length=1, max_length=240),
    limit: int = Query(default=50, ge=1, le=200),
) -> dict[str, Any]:
    _require_api_token(request)
    tenant_id = _safe_segment(tenantId, "default")
    campaign_id = str(campaignId or "").strip()

    with _db() as con:
        state_row = con.execute(
            """
            SELECT tenant_id, campaign_id, server_revision, server_sync_id,
                   device_id, updated_at, received_at, payload_sha256,
                   payload_json, conflict_policy
            FROM campaign_states
            WHERE tenant_id = ? AND campaign_id = ?
            """,
            (tenant_id, campaign_id),
        ).fetchone()
        rows = con.execute(
            """
            SELECT tenant_id, campaign_id, server_revision, server_sync_id,
                   device_id, updated_at, received_at, payload_sha256,
                   payload_json, conflict_policy, conflict_detected, conflict_reason
            FROM campaign_revisions
            WHERE tenant_id = ? AND campaign_id = ?
            ORDER BY server_revision DESC
            LIMIT ?
            """,
            (tenant_id, campaign_id, limit),
        ).fetchall()

    if state_row is None and not rows:
        raise HTTPException(status_code=404, detail="Unknown campaign")

    return {
        "status": "ok",
        "type": "openirn.campaignRevisions",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "storage": "sqlite",
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "campaignId": campaign_id,
        "current": _public_campaign_state_from_row(state_row) if state_row else None,
        "revisionCount": len(rows),
        "revisions": [_public_campaign_revision_from_row(row) for row in rows],
    }


@app.get("/campaigns/conflicts")
def campaign_conflicts(
    request: Request,
    tenantId: str = Query(default="default", min_length=1, max_length=80),
    campaignId: str = Query(default="", max_length=240),
    limit: int = Query(default=50, ge=1, le=200),
) -> dict[str, Any]:
    _require_api_token(request)
    tenant_id = _safe_segment(tenantId, "default")
    campaign_id = str(campaignId or "").strip()

    with _db() as con:
        if campaign_id:
            rows = con.execute(
                """
                SELECT tenant_id, campaign_id, server_revision, server_sync_id,
                       device_id, updated_at, received_at, payload_sha256,
                       payload_json, conflict_policy, conflict_detected, conflict_reason
                FROM campaign_revisions
                WHERE tenant_id = ? AND campaign_id = ? AND conflict_detected = 1
                ORDER BY received_at DESC, server_revision DESC
                LIMIT ?
                """,
                (tenant_id, campaign_id, limit),
            ).fetchall()
        else:
            rows = con.execute(
                """
                SELECT tenant_id, campaign_id, server_revision, server_sync_id,
                       device_id, updated_at, received_at, payload_sha256,
                       payload_json, conflict_policy, conflict_detected, conflict_reason
                FROM campaign_revisions
                WHERE tenant_id = ? AND conflict_detected = 1
                ORDER BY received_at DESC, server_revision DESC
                LIMIT ?
                """,
                (tenant_id, limit),
            ).fetchall()

    return {
        "status": "ok",
        "type": "openirn.campaignConflicts",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "storage": "sqlite",
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "campaignId": campaign_id or None,
        "conflictCount": len(rows),
        "conflicts": [_public_campaign_revision_from_row(row) for row in rows],
    }


@app.get("/campaigns/revision")
def campaign_revision(
    request: Request,
    tenantId: str = Query(default="default", min_length=1, max_length=80),
    campaignId: str = Query(min_length=1, max_length=240),
    serverRevision: int = Query(ge=1),
) -> dict[str, Any]:
    _require_api_token(request)
    tenant_id = _safe_segment(tenantId, "default")
    campaign_id = str(campaignId or "").strip()

    with _db() as con:
        row = con.execute(
            """
            SELECT tenant_id, campaign_id, server_revision, server_sync_id,
                   device_id, updated_at, received_at, payload_sha256,
                   payload_json, conflict_policy, conflict_detected, conflict_reason
            FROM campaign_revisions
            WHERE tenant_id = ? AND campaign_id = ? AND server_revision = ?
            """,
            (tenant_id, campaign_id, serverRevision),
        ).fetchone()

    if row is None:
        raise HTTPException(status_code=404, detail="Unknown campaign revision")

    return {
        "status": "ok",
        "type": "openirn.campaignRevision",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "storage": "sqlite",
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "revision": _public_campaign_revision_from_row(row, include_payload=True),
    }


@app.post("/campaigns/restore")
async def campaign_restore(request: Request) -> dict[str, Any]:
    _require_api_token(request)

    try:
        payload = await request.json()
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail="Invalid JSON payload") from exc

    if not isinstance(payload, dict):
        raise HTTPException(status_code=400, detail="Payload must be a JSON object")

    tenant_id = _safe_segment(payload.get("tenantId"), "default")
    campaign_id = str(payload.get("campaignId") or "").strip()
    restored_by_user_id = str(payload.get("restoredByUserId") or "").strip()
    reason = str(payload.get("reason") or "admin_restore").strip()[:240] or "admin_restore"

    try:
        source_revision = int(payload.get("serverRevision"))
    except (TypeError, ValueError) as exc:
        raise HTTPException(status_code=400, detail="serverRevision must be an integer") from exc

    if not campaign_id:
        raise HTTPException(status_code=400, detail="Missing campaignId")
    if source_revision < 1:
        raise HTTPException(status_code=400, detail="serverRevision must be greater than zero")

    restored_at = _utc_now().isoformat()
    server_sync_id = f"restore_{_utc_now().strftime('%Y%m%dT%H%M%SZ')}_{uuid.uuid4().hex[:12]}"
    device_id = _safe_segment(restored_by_user_id or "server-restore", "server-restore")

    with _db() as con:
        with con:
            _ensure_tenant(con, tenant_id)
            source_row = con.execute(
                """
                SELECT tenant_id, campaign_id, server_revision, server_sync_id,
                       device_id, updated_at, received_at, payload_sha256,
                       payload_json, conflict_policy, conflict_detected, conflict_reason
                FROM campaign_revisions
                WHERE tenant_id = ? AND campaign_id = ? AND server_revision = ?
                """,
                (tenant_id, campaign_id, source_revision),
            ).fetchone()
            if source_row is None:
                raise HTTPException(status_code=404, detail="Unknown campaign revision")

            state_row = con.execute(
                """
                SELECT server_revision, payload_sha256, device_id
                FROM campaign_states
                WHERE tenant_id = ? AND campaign_id = ?
                """,
                (tenant_id, campaign_id),
            ).fetchone()
            if state_row is None:
                raise HTTPException(status_code=404, detail="Unknown campaign state")

            current_revision = int(state_row["server_revision"] or 0)
            source_payload = _parse_json(source_row["payload_json"], {})
            if not isinstance(source_payload, dict):
                raise HTTPException(status_code=500, detail="Stored revision payload is invalid")

            source_sha256 = str(source_row["payload_sha256"] or _json_sha256(source_payload))
            if current_revision == source_revision and str(state_row["payload_sha256"] or "") == source_sha256:
                return {
                    "status": "no_change",
                    "type": "openirn.campaignRestore",
                    "application": "OpenIRN API",
                    "version": APP_VERSION,
                    "storage": "sqlite",
                    "tenantId": tenant_id,
                    "serverTime": _utc_now().isoformat(),
                    "campaignId": campaign_id,
                    "sourceRevision": source_revision,
                    "currentRevision": current_revision,
                    "message": "The requested revision is already current",
                }

            new_revision = current_revision + 1
            restore_metadata = {
                "campaignId": campaign_id,
                "sourceRevision": source_revision,
                "newRevision": new_revision,
                "restoredByUserId": restored_by_user_id or None,
                "reason": reason,
                "sourceServerSyncId": source_row["server_sync_id"],
            }
            restore_payload = {
                "type": "openirn.syncPush",
                "sync": {
                    "tenantId": tenant_id,
                    "deviceId": device_id,
                    "mode": "admin_restore",
                },
                "generatedAt": restored_at,
                "campaigns": [source_payload],
                "restore": restore_metadata,
            }
            restore_payload_sha256 = _json_sha256(restore_payload)
            envelope = {
                "serverSyncId": server_sync_id,
                "receivedAt": restored_at,
                "tenantId": tenant_id,
                "deviceId": device_id,
                "payloadSha256": restore_payload_sha256,
                "payload": restore_payload,
            }

            con.execute(
                """
                INSERT INTO sync_snapshots(
                    tenant_id, server_sync_id, device_id, received_at,
                    payload_sha256, campaign_count, payload_json, envelope_json
                ) VALUES (?, ?, ?, ?, ?, 1, ?, ?)
                """,
                (
                    tenant_id,
                    server_sync_id,
                    device_id,
                    restored_at,
                    restore_payload_sha256,
                    _canonical_json(restore_payload),
                    _canonical_json(envelope),
                ),
            )

            con.execute(
                """
                INSERT INTO campaign_revisions(
                    tenant_id, campaign_id, server_revision, server_sync_id,
                    device_id, updated_at, received_at, payload_sha256,
                    payload_json, conflict_policy, conflict_detected, conflict_reason
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'admin_restore', 0, ?)
                """,
                (
                    tenant_id,
                    campaign_id,
                    new_revision,
                    server_sync_id,
                    device_id,
                    restored_at,
                    restored_at,
                    source_sha256,
                    _canonical_json(source_payload),
                    f"restored_from_revision_{source_revision}",
                ),
            )

            con.execute(
                """
                INSERT INTO campaign_states(
                    tenant_id, campaign_id, server_revision, server_sync_id,
                    device_id, updated_at, received_at, payload_sha256,
                    payload_json, conflict_policy
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'admin_restore')
                ON CONFLICT(tenant_id, campaign_id) DO UPDATE SET
                    server_revision = excluded.server_revision,
                    server_sync_id = excluded.server_sync_id,
                    device_id = excluded.device_id,
                    updated_at = excluded.updated_at,
                    received_at = excluded.received_at,
                    payload_sha256 = excluded.payload_sha256,
                    payload_json = excluded.payload_json,
                    conflict_policy = excluded.conflict_policy
                """,
                (
                    tenant_id,
                    campaign_id,
                    new_revision,
                    server_sync_id,
                    device_id,
                    restored_at,
                    restored_at,
                    source_sha256,
                    _canonical_json(source_payload),
                ),
            )

            con.execute(
                """
                INSERT INTO sync_events(
                    tenant_id, event_type, server_sync_id, campaign_id,
                    device_id, created_at, payload_json
                ) VALUES (?, 'campaign_revision_restored', ?, ?, ?, ?, ?)
                """,
                (
                    tenant_id,
                    server_sync_id,
                    campaign_id,
                    device_id,
                    restored_at,
                    _canonical_json(restore_metadata),
                ),
            )

    return {
        "status": "accepted",
        "type": "openirn.campaignRestore",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "storage": "sqlite",
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "campaignId": campaign_id,
        "sourceRevision": source_revision,
        "serverRevision": new_revision,
        "serverSyncId": server_sync_id,
        "deviceId": device_id,
        "payloadSha256": source_sha256,
        "conflictPolicy": "admin_restore",
    }


@app.get("/maintenance/status")
def maintenance_status(
    request: Request,
    limit: int = Query(default=10, ge=1, le=50),
) -> dict[str, Any]:
    _require_api_token(request)
    return _maintenance_status(limit=limit)


@app.post("/maintenance/backup")
async def maintenance_backup(request: Request) -> dict[str, Any]:
    _require_api_token(request)
    try:
        payload = await request.json()
    except json.JSONDecodeError:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    triggered_by_user_id = str(payload.get("triggeredByUserId") or "").strip() or None
    backup = _create_sqlite_backup(triggered_by_user_id=triggered_by_user_id)
    return {
        "status": "ok",
        "type": "openirn.sqliteBackupCreated",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "serverTime": _utc_now().isoformat(),
        "backup": backup,
        "maintenance": _maintenance_status(limit=10),
    }


@app.post("/maintenance/backups/{backup_name}/restore")
async def maintenance_restore_backup(backup_name: str, request: Request) -> dict[str, Any]:
    _require_api_token(request)
    try:
        payload = await request.json()
    except json.JSONDecodeError:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    triggered_by_user_id = str(payload.get("triggeredByUserId") or "").strip() or None
    restore = _restore_sqlite_backup(backup_name, triggered_by_user_id=triggered_by_user_id)
    return {
        "status": "ok",
        "type": "openirn.sqliteBackupRestored",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "serverTime": _utc_now().isoformat(),
        "restore": restore,
        "maintenance": _maintenance_status(limit=10),
    }


@app.delete("/maintenance/backups/{backup_name}")
def maintenance_delete_backup(backup_name: str, request: Request) -> dict[str, Any]:
    _require_api_token(request)
    deletion = _delete_sqlite_backup(backup_name)
    return {
        "status": "ok",
        "type": "openirn.sqliteBackupDeleted",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "serverTime": _utc_now().isoformat(),
        "deletion": deletion,
        "maintenance": _maintenance_status(limit=10),
    }


@app.get("/sync/events")
async def sync_events(
    request: Request,
    tenantId: str = Query(default="default", min_length=1, max_length=80),
    since: str = Query(default="", max_length=120),
    interval: float = Query(default=2.0, ge=1.0, le=30.0),
) -> StreamingResponse:
    tenant_id = _safe_segment(tenantId, "default")
    _require_sync_read_access(request, tenant_id)
    last_server_sync_id = str(since or "").strip()

    async def event_stream():
        nonlocal last_server_sync_id
        while True:
            if await request.is_disconnected():
                break

            with _db() as con:
                latest_row = con.execute(
                    """
                    SELECT tenant_id, server_sync_id, device_id, received_at,
                           payload_sha256, campaign_count, payload_json
                    FROM sync_snapshots
                    WHERE tenant_id = ?
                    ORDER BY received_at DESC, server_sync_id DESC
                    LIMIT 1
                    """,
                    (tenant_id,),
                ).fetchone()

            latest_snapshot = _snapshot_summary_from_row(latest_row)
            current_server_sync_id = str((latest_snapshot or {}).get("serverSyncId") or "").strip()
            server_time = _utc_now().isoformat()

            if latest_snapshot and current_server_sync_id != last_server_sync_id:
                last_server_sync_id = current_server_sync_id
                payload = {
                    "type": "openirn.syncEvent",
                    "event": "snapshot",
                    "application": "OpenIRN API",
                    "version": APP_VERSION,
                    "storage": "sqlite",
                    "tenantId": tenant_id,
                    "serverTime": server_time,
                    "latestSnapshot": latest_snapshot,
                }
                yield f"event: snapshot\ndata: {json.dumps(payload, ensure_ascii=False, separators=(',', ':'))}\n\n"
            else:
                payload = {
                    "type": "openirn.heartbeat",
                    "event": "heartbeat",
                    "application": "OpenIRN API",
                    "version": APP_VERSION,
                    "storage": "sqlite",
                    "tenantId": tenant_id,
                    "serverTime": server_time,
                    "latestServerSyncId": current_server_sync_id or None,
                }
                yield f"event: heartbeat\ndata: {json.dumps(payload, ensure_ascii=False, separators=(',', ':'))}\n\n"

            await asyncio.sleep(interval)

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
