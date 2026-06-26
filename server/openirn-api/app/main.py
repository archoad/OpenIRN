from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

APP_VERSION = "0.2.0"
DATA_DIR = Path(os.environ.get("OPENIRN_API_DATA_DIR", "/var/lib/openirn-api"))
SYNC_PUSH_DIR = DATA_DIR / "sync-push"
USERS_DIR = DATA_DIR / "users"
TENANT_RE = re.compile(r"[^a-zA-Z0-9_.-]+")
PIN_DEFAULT = os.environ.get("OPENIRN_DEFAULT_USER_PIN", "0000")
PIN_ITERATIONS = int(os.environ.get("OPENIRN_PIN_ITERATIONS", "200000"))


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
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _safe_segment(value: Any, fallback: str) -> str:
    raw = str(value or "").strip()
    if not raw:
        return fallback
    cleaned = TENANT_RE.sub("_", raw)
    return cleaned[:80] or fallback


def _json_sha256(payload: dict[str, Any]) -> str:
    raw = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


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


def _require_api_token(request: Request) -> None:
    expected_token = _configured_api_token()
    if not expected_token:
        raise HTTPException(
            status_code=503,
            detail="OpenIRN API token is not configured on the server",
        )

    provided_token = _extract_bearer_token(request)
    if not provided_token:
        raise HTTPException(status_code=401, detail="Missing Bearer token")

    if not hmac.compare_digest(provided_token, expected_token):
        raise HTTPException(status_code=403, detail="Invalid API token")


def _load_sync_envelopes(tenant_id: str) -> list[dict[str, Any]]:
    tenant_dir = SYNC_PUSH_DIR / tenant_id
    if not tenant_dir.exists():
        return []

    envelopes: list[dict[str, Any]] = []
    for path in tenant_dir.glob("*/*.json"):
        if not path.is_file():
            continue
        try:
            envelope = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(envelope, dict):
            envelopes.append(envelope)

    envelopes.sort(key=lambda item: str(item.get("receivedAt", "")), reverse=True)
    return envelopes


def _public_snapshot(envelope: dict[str, Any]) -> dict[str, Any]:
    payload = envelope.get("payload")
    campaigns = payload.get("campaigns") if isinstance(payload, dict) else None
    return {
        "serverSyncId": envelope.get("serverSyncId"),
        "receivedAt": envelope.get("receivedAt"),
        "tenantId": envelope.get("tenantId"),
        "deviceId": envelope.get("deviceId"),
        "payloadSha256": envelope.get("payloadSha256"),
        "campaignCount": len(campaigns) if isinstance(campaigns, list) else 0,
        "payload": payload if isinstance(payload, dict) else None,
    }


def _snapshot_summary(envelope: dict[str, Any]) -> dict[str, Any]:
    public = _public_snapshot(envelope)
    public.pop("payload", None)
    return public


def _campaign_count(envelope: dict[str, Any]) -> int:
    payload = envelope.get("payload")
    campaigns = payload.get("campaigns") if isinstance(payload, dict) else None
    return len(campaigns) if isinstance(campaigns, list) else 0


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


def _sanitize_user(raw_user: Any) -> dict[str, Any] | None:
    if not isinstance(raw_user, dict):
        return None

    user_id = str(raw_user.get("id") or "").strip()
    if not user_id:
        return None

    role = str(raw_user.get("role") or raw_user.get("roleLabel") or "reader").strip().lower()
    role_aliases = {
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
    normalized_role = role_aliases.get(role, "reader")

    created_at = str(raw_user.get("createdAt") or _utc_now().isoformat())
    updated_at = str(raw_user.get("updatedAt") or created_at)
    active = raw_user.get("active")

    return {
        "id": user_id,
        "firstName": str(raw_user.get("firstName") or "").strip(),
        "lastName": str(raw_user.get("lastName") or "").strip(),
        "email": str(raw_user.get("email") or "").strip().lower(),
        "role": normalized_role,
        "active": active if isinstance(active, bool) else True,
        "createdAt": created_at,
        "updatedAt": updated_at,
    }


def _users_file(tenant_id: str) -> Path:
    return USERS_DIR / tenant_id / "users.json"

def _credentials_file(tenant_id: str) -> Path:
    return USERS_DIR / tenant_id / "credentials.json"


def _pin_hash(pin: str, salt: str, iterations: int = PIN_ITERATIONS) -> str:
    return hashlib.pbkdf2_hmac(
        "sha256",
        str(pin or "").encode("utf-8"),
        salt.encode("utf-8"),
        iterations,
    ).hex()


def _load_user_credentials(tenant_id: str) -> dict[str, Any]:
    path = _credentials_file(tenant_id)
    if not path.exists():
        return {"schemaVersion": 1, "users": {}}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"schemaVersion": 1, "users": {}}
    if not isinstance(payload, dict):
        return {"schemaVersion": 1, "users": {}}
    users = payload.get("users")
    if not isinstance(users, dict):
        payload["users"] = {}
    return payload


def _save_user_credentials(tenant_id: str, credentials: dict[str, Any]) -> None:
    target = _credentials_file(tenant_id)
    target.parent.mkdir(parents=True, exist_ok=True)
    credentials["schemaVersion"] = 1
    credentials["type"] = "openirn.userCredentials"
    credentials["application"] = "OpenIRN API"
    credentials["version"] = APP_VERSION
    credentials["tenantId"] = tenant_id
    credentials["updatedAt"] = _utc_now().isoformat()
    target.write_text(json.dumps(credentials, ensure_ascii=False, indent=2), encoding="utf-8")


def _set_user_pin(tenant_id: str, user_id: str, pin: str, *, requires_change: bool) -> None:
    cleaned_pin = str(pin or "").strip()
    if len(cleaned_pin) < 4 or len(cleaned_pin) > 32:
        raise HTTPException(status_code=400, detail="PIN must contain between 4 and 32 characters")
    credentials = _load_user_credentials(tenant_id)
    users = credentials.setdefault("users", {})
    if not isinstance(users, dict):
        users = {}
        credentials["users"] = users
    salt = uuid.uuid4().hex
    users[user_id] = {
        "algorithm": "pbkdf2_sha256",
        "iterations": PIN_ITERATIONS,
        "salt": salt,
        "pinHash": _pin_hash(cleaned_pin, salt, PIN_ITERATIONS),
        "requiresChange": requires_change,
        "updatedAt": _utc_now().isoformat(),
    }
    _save_user_credentials(tenant_id, credentials)


def _ensure_user_credentials(tenant_id: str, users: list[dict[str, Any]]) -> None:
    credentials = _load_user_credentials(tenant_id)
    credential_users = credentials.setdefault("users", {})
    if not isinstance(credential_users, dict):
        credential_users = {}
        credentials["users"] = credential_users

    changed = False
    for user in users:
        user_id = str(user.get("id") or "").strip()
        if not user_id:
            continue
        if user_id in credential_users:
            continue
        salt = uuid.uuid4().hex
        credential_users[user_id] = {
            "algorithm": "pbkdf2_sha256",
            "iterations": PIN_ITERATIONS,
            "salt": salt,
            "pinHash": _pin_hash(PIN_DEFAULT, salt, PIN_ITERATIONS),
            "requiresChange": True,
            "updatedAt": _utc_now().isoformat(),
        }
        changed = True

    if changed:
        _save_user_credentials(tenant_id, credentials)


def _verify_user_pin(tenant_id: str, user_id: str, pin: str) -> tuple[bool, bool]:
    credentials = _load_user_credentials(tenant_id)
    credential_users = credentials.get("users")
    if not isinstance(credential_users, dict):
        return (False, False)
    credential = credential_users.get(user_id)
    if not isinstance(credential, dict):
        return (False, False)

    salt = str(credential.get("salt") or "")
    expected_hash = str(credential.get("pinHash") or "")
    iterations = int(credential.get("iterations") or PIN_ITERATIONS)
    if not salt or not expected_hash:
        return (False, False)

    provided_hash = _pin_hash(str(pin or "").strip(), salt, iterations)
    accepted = hmac.compare_digest(provided_hash, expected_hash)
    return (accepted, credential.get("requiresChange") is True)



def _load_central_users(tenant_id: str) -> list[dict[str, Any]]:
    path = _users_file(tenant_id)
    if not path.exists():
        return []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []

    raw_users = payload.get("users") if isinstance(payload, dict) else None
    if not isinstance(raw_users, list):
        return []

    users: list[dict[str, Any]] = []
    for raw_user in raw_users:
        user = _sanitize_user(raw_user)
        if user:
            users.append(user)
    return _sort_users(users)


def _sort_users(users: list[dict[str, Any]]) -> list[dict[str, Any]]:
    def key(user: dict[str, Any]) -> tuple[int, str]:
        active_weight = 0 if user.get("active") is True else 1
        display = " ".join(
            part for part in [
                str(user.get("firstName") or "").strip(),
                str(user.get("lastName") or "").strip(),
                str(user.get("email") or "").strip(),
                str(user.get("id") or "").strip(),
            ]
            if part
        ).lower()
        return (active_weight, display)

    return sorted(users, key=key)


def _save_central_users(tenant_id: str, users: list[dict[str, Any]]) -> None:
    target = _users_file(tenant_id)
    target.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schemaVersion": 1,
        "type": "openirn.centralUsers",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "tenantId": tenant_id,
        "updatedAt": _utc_now().isoformat(),
        "userCount": len(users),
        "users": _sort_users(users),
    }
    target.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    _ensure_user_credentials(tenant_id, payload["users"])


def _merge_central_users(tenant_id: str, raw_users: Any) -> int:
    if not isinstance(raw_users, list):
        return 0

    by_id: dict[str, dict[str, Any]] = {user["id"]: user for user in _load_central_users(tenant_id)}
    changed = 0
    for raw_user in raw_users:
        user = _sanitize_user(raw_user)
        if not user:
            continue
        existing = by_id.get(user["id"])
        if existing is None or _parse_datetime(user.get("updatedAt")) >= _parse_datetime(existing.get("updatedAt")):
            by_id[user["id"]] = user
            changed += 1

    if changed:
        _save_central_users(tenant_id, list(by_id.values()))
    return changed


def _seed_central_users_from_latest_snapshot(tenant_id: str) -> None:
    if _load_central_users(tenant_id):
        return
    envelopes = _load_sync_envelopes(tenant_id)
    for envelope in envelopes:
        payload = envelope.get("payload")
        if isinstance(payload, dict):
            merged = _merge_central_users(tenant_id, payload.get("users"))
            if merged:
                return


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "authRequired": True,
        "authMode": "bearer_token",
        "endpoints": ["/health", "/auth/verify", "/users", "/users/replace", "/users/pin", "/sync/push", "/sync/status", "/sync/pull", "/sync/events"],
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
    campaigns = payload.get("campaigns")
    if not isinstance(campaigns, list):
        raise HTTPException(status_code=400, detail="Missing campaigns array")

    received_at = _utc_now()
    server_sync_id = f"sync_{received_at.strftime('%Y%m%dT%H%M%SZ')}_{uuid.uuid4().hex[:12]}"
    payload_sha256 = _json_sha256(payload)

    target_dir = SYNC_PUSH_DIR / tenant_id / device_id
    target_dir.mkdir(parents=True, exist_ok=True)
    target_file = target_dir / f"{server_sync_id}.json"

    envelope = {
        "serverSyncId": server_sync_id,
        "receivedAt": received_at.isoformat(),
        "tenantId": tenant_id,
        "deviceId": device_id,
        "payloadSha256": payload_sha256,
        "payload": payload,
    }

    target_file.write_text(json.dumps(envelope, ensure_ascii=False, indent=2), encoding="utf-8")
    central_user_count = _merge_central_users(tenant_id, payload.get("users"))

    return {
        "status": "accepted",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "serverSyncId": server_sync_id,
        "receivedAt": received_at.isoformat(),
        "tenantId": tenant_id,
        "deviceId": device_id,
        "payloadSha256": payload_sha256,
        "stored": True,
        "campaignCount": len(campaigns),
        "centralUserCount": central_user_count,
        "pathHint": str(target_file),
    }


@app.post("/auth/verify")
async def auth_verify(request: Request) -> dict[str, Any]:
    _require_api_token(request)

    try:
        payload = await request.json()
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail="Invalid JSON payload") from exc

    if not isinstance(payload, dict):
        raise HTTPException(status_code=400, detail="Payload must be a JSON object")

    tenant_id = _safe_segment(payload.get("tenantId"), "default")
    user_id = str(payload.get("userId") or "").strip()
    pin = str(payload.get("pin") or "")
    if not user_id:
        raise HTTPException(status_code=400, detail="Missing userId")
    if not pin.strip():
        raise HTTPException(status_code=400, detail="Missing PIN")

    _seed_central_users_from_latest_snapshot(tenant_id)
    central_users = _load_central_users(tenant_id)
    _ensure_user_credentials(tenant_id, central_users)

    user = next((candidate for candidate in central_users if candidate.get("id") == user_id), None)
    if user is None:
        raise HTTPException(status_code=404, detail="Unknown user")
    if user.get("active") is not True:
        raise HTTPException(status_code=403, detail="Inactive user")

    accepted, requires_change = _verify_user_pin(tenant_id, user_id, pin)
    if not accepted:
        raise HTTPException(status_code=403, detail="Invalid user code")

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
    }


@app.get("/users")
def users(
    request: Request,
    tenantId: str = Query(default="default", min_length=1, max_length=80),
) -> dict[str, Any]:
    _require_api_token(request)

    tenant_id = _safe_segment(tenantId, "default")
    _seed_central_users_from_latest_snapshot(tenant_id)
    central_users = _load_central_users(tenant_id)

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

    users_to_save: list[dict[str, Any]] = []
    for raw_user in raw_users:
        user = _sanitize_user(raw_user)
        if user:
            users_to_save.append(user)

    _save_central_users(tenant_id, users_to_save)

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

    _seed_central_users_from_latest_snapshot(tenant_id)
    central_users = _load_central_users(tenant_id)
    if not any(user.get("id") == user_id for user in central_users):
        raise HTTPException(status_code=404, detail="Unknown user")

    _set_user_pin(tenant_id, user_id, pin, requires_change=False)
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
def sync_status(
    request: Request,
    tenantId: str = Query(default="default", min_length=1, max_length=80),
) -> dict[str, Any]:
    _require_api_token(request)

    tenant_id = _safe_segment(tenantId, "default")
    envelopes = _load_sync_envelopes(tenant_id)
    device_ids = {str(envelope.get("deviceId", "")) for envelope in envelopes if envelope.get("deviceId")}
    campaign_count = sum(_campaign_count(envelope) for envelope in envelopes)
    latest_snapshot = _snapshot_summary(envelopes[0]) if envelopes else None

    return {
        "status": "ok",
        "type": "openirn.syncStatus",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "snapshotCount": len(envelopes),
        "deviceCount": len(device_ids),
        "campaignCount": campaign_count,
        "latestSnapshot": latest_snapshot,
    }


@app.get("/sync/events")
async def sync_events(
    request: Request,
    tenantId: str = Query(default="default", min_length=1, max_length=80),
    since: str = Query(default="", max_length=120),
    interval: float = Query(default=2.0, ge=1.0, le=30.0),
) -> StreamingResponse:
    _require_api_token(request)

    tenant_id = _safe_segment(tenantId, "default")
    last_server_sync_id = str(since or "").strip()

    async def event_stream():
        nonlocal last_server_sync_id
        while True:
            if await request.is_disconnected():
                break

            envelopes = _load_sync_envelopes(tenant_id)
            latest_snapshot = _snapshot_summary(envelopes[0]) if envelopes else None
            current_server_sync_id = str((latest_snapshot or {}).get("serverSyncId") or "").strip()
            server_time = _utc_now().isoformat()

            if latest_snapshot and current_server_sync_id != last_server_sync_id:
                last_server_sync_id = current_server_sync_id
                payload = {
                    "type": "openirn.syncEvent",
                    "event": "snapshot",
                    "application": "OpenIRN API",
                    "version": APP_VERSION,
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


@app.get("/sync/pull")
def sync_pull(
    request: Request,
    tenantId: str = Query(default="default", min_length=1, max_length=80),
    limit: int = Query(default=10, ge=1, le=50),
) -> dict[str, Any]:
    _require_api_token(request)

    tenant_id = _safe_segment(tenantId, "default")
    envelopes = _load_sync_envelopes(tenant_id)
    snapshots = [_public_snapshot(envelope) for envelope in envelopes[:limit]]

    return {
        "status": "ok",
        "type": "openirn.syncPull",
        "application": "OpenIRN API",
        "version": APP_VERSION,
        "tenantId": tenant_id,
        "serverTime": _utc_now().isoformat(),
        "snapshotCount": len(snapshots),
        "availableSnapshotCount": len(envelopes),
        "limit": limit,
        "snapshots": snapshots,
    }
