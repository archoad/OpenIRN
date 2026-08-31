from __future__ import annotations

import contextvars
import hashlib
import hmac
import json
import logging
import os
import re
import sys
import time
import uuid
from datetime import datetime, timezone
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any, Awaitable, Callable

ACCESS_LOG_PATH_ENV = "OPENIRN_API_ACCESS_LOG_PATH"
ACCESS_LOG_MAX_BYTES_ENV = "OPENIRN_API_ACCESS_LOG_MAX_BYTES"
ACCESS_LOG_BACKUP_COUNT_ENV = "OPENIRN_API_ACCESS_LOG_BACKUP_COUNT"
SECURITY_LOG_PATH_ENV = "OPENIRN_API_SECURITY_LOG_PATH"
SECURITY_LOG_MAX_BYTES_ENV = "OPENIRN_API_SECURITY_LOG_MAX_BYTES"
SECURITY_LOG_BACKUP_COUNT_ENV = "OPENIRN_API_SECURITY_LOG_BACKUP_COUNT"
OPERATIONS_LOG_PATH_ENV = "OPENIRN_API_OPERATIONS_LOG_PATH"
OPERATIONS_LOG_MAX_BYTES_ENV = "OPENIRN_API_OPERATIONS_LOG_MAX_BYTES"
OPERATIONS_LOG_BACKUP_COUNT_ENV = "OPENIRN_API_OPERATIONS_LOG_BACKUP_COUNT"
OBSERVABILITY_HASH_SECRET_ENV = "OPENIRN_API_OBSERVABILITY_HASH_SECRET"

DEFAULT_ACCESS_LOG_MAX_BYTES = 10 * 1024 * 1024
DEFAULT_ACCESS_LOG_BACKUP_COUNT = 7
UNMATCHED_ROUTE = "/__unmatched__"

_REQUEST_TRACE_ID = contextvars.ContextVar("openirn_request_trace_id", default="")
_SAFE_EVENT_TYPE_RE = re.compile(r"^[a-z][a-z0-9_.-]{0,119}$")
_SAFE_KEYWORD_RE = re.compile(r"^[a-zA-Z0-9_.:-]{1,120}$")

_SECURITY_INTEGER_ATTRIBUTES = {
    "activationChangedCount": "activation_changed_count",
    "administratorCount": "administrator_count",
    "administratorCreatedCount": "administrator_created_count",
    "administratorGrantedCount": "administrator_granted_count",
    "administratorRevokedCount": "administrator_revoked_count",
    "createdCount": "created_count",
    "deletedCount": "deleted_count",
    "expiredStaleRequestCount": "expired_stale_request_count",
    "idleTimeoutMinutes": "idle_timeout_minutes",
    "limit": "limit",
    "pendingCount": "pending_count",
    "roleChangedCount": "role_changed_count",
    "updatedCount": "updated_count",
    "windowMinutes": "window_minutes",
}
_SECURITY_BOOLEAN_ATTRIBUTES = {
    "clientProvidedDeviceId": "client_provided_device_id",
    "globalSolutionAdministrator": "global_solution_administrator",
    "knownTerminal": "known_terminal",
    "requiresChange": "requires_change",
    "sessionsRevoked": "sessions_revoked",
    "submittedNameIgnored": "submitted_name_ignored",
    "terminalAlreadyKnown": "terminal_already_known",
}
_SECURITY_KEYWORD_ATTRIBUTES = {
    "authMode": "auth_mode",
    "operation": "operation",
    "previousStatus": "previous_status",
    "scope": "scope",
    "userRole": "user_role",
}

EventEmitter = Callable[[dict[str, Any]], None]


def _positive_int_env(name: str, default: int) -> int:
    raw = os.environ.get(name, str(default)).strip()
    try:
        value = int(raw)
    except ValueError as exc:
        raise RuntimeError(f"{name} doit être un entier strictement positif") from exc
    if value <= 0:
        raise RuntimeError(f"{name} doit être un entier strictement positif")
    return value


def _access_logger() -> logging.Logger:
    logger = logging.getLogger("openirn.api.access")
    if getattr(logger, "_openirn_configured", False):
        return logger

    path = os.environ.get(ACCESS_LOG_PATH_ENV, "-").strip() or "-"
    if path == "-":
        handler: logging.Handler = logging.StreamHandler(sys.stdout)
    else:
        log_path = Path(path)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        handler = RotatingFileHandler(
            log_path,
            maxBytes=_positive_int_env(
                ACCESS_LOG_MAX_BYTES_ENV,
                DEFAULT_ACCESS_LOG_MAX_BYTES,
            ),
            backupCount=_positive_int_env(
                ACCESS_LOG_BACKUP_COUNT_ENV,
                DEFAULT_ACCESS_LOG_BACKUP_COUNT,
            ),
            encoding="utf-8",
        )

    handler.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    setattr(logger, "_openirn_configured", True)
    return logger


def _security_logger() -> logging.Logger:
    logger = logging.getLogger("openirn.api.security")
    if getattr(logger, "_openirn_configured", False):
        return logger

    path = os.environ.get(SECURITY_LOG_PATH_ENV, "-").strip() or "-"
    if path == "-":
        handler: logging.Handler = logging.StreamHandler(sys.stdout)
    else:
        log_path = Path(path)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        handler = RotatingFileHandler(
            log_path,
            maxBytes=_positive_int_env(
                SECURITY_LOG_MAX_BYTES_ENV,
                DEFAULT_ACCESS_LOG_MAX_BYTES,
            ),
            backupCount=_positive_int_env(
                SECURITY_LOG_BACKUP_COUNT_ENV,
                DEFAULT_ACCESS_LOG_BACKUP_COUNT,
            ),
            encoding="utf-8",
        )

    handler.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    setattr(logger, "_openirn_configured", True)
    return logger


def _operations_logger() -> logging.Logger:
    logger = logging.getLogger("openirn.api.operations")
    if getattr(logger, "_openirn_configured", False):
        return logger

    path = os.environ.get(OPERATIONS_LOG_PATH_ENV, "-").strip() or "-"
    if path == "-":
        handler: logging.Handler = logging.StreamHandler(sys.stdout)
    else:
        log_path = Path(path)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        handler = RotatingFileHandler(
            log_path,
            maxBytes=_positive_int_env(
                OPERATIONS_LOG_MAX_BYTES_ENV,
                DEFAULT_ACCESS_LOG_MAX_BYTES,
            ),
            backupCount=_positive_int_env(
                OPERATIONS_LOG_BACKUP_COUNT_ENV,
                DEFAULT_ACCESS_LOG_BACKUP_COUNT,
            ),
            encoding="utf-8",
        )

    handler.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    setattr(logger, "_openirn_configured", True)
    return logger


def emit_access_event(event: dict[str, Any]) -> None:
    _access_logger().info(
        json.dumps(
            event,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
    )


def emit_security_event(event: dict[str, Any]) -> None:
    try:
        _security_logger().info(
            json.dumps(
                event,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            )
        )
    except Exception:
        logging.getLogger(__name__).exception(
            "Impossible d'écrire l'événement de sécurité OpenIRN"
        )


def emit_operation_event(event: dict[str, Any]) -> None:
    try:
        _operations_logger().info(
            json.dumps(
                event,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            )
        )
    except Exception:
        logging.getLogger(__name__).exception(
            "Impossible d'écrire l'événement d'exploitation OpenIRN"
        )


def current_trace_id() -> str:
    return _REQUEST_TRACE_ID.get()


def _pseudonymize_identity(kind: str, value: Any) -> str:
    raw = str(value or "").strip()
    secret = os.environ.get(OBSERVABILITY_HASH_SECRET_ENV, "").strip()
    if not raw or len(secret) < 32:
        return ""
    return hmac.new(
        secret.encode("utf-8"),
        f"{kind}:{raw}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def _safe_event_type(value: Any, fallback: str = "security.event") -> str:
    raw = str(value or "").strip().lower()
    return raw if _SAFE_EVENT_TYPE_RE.fullmatch(raw) else fallback


def _safe_keyword(value: Any, fallback: str = "") -> str:
    raw = str(value or "").strip()
    return raw[:120] if _SAFE_KEYWORD_RE.fullmatch(raw) else fallback


def _security_event_category(event_type: str) -> list[str]:
    if event_type.startswith(("auth.", "authorization.", "session.")):
        return ["authentication"]
    return ["iam"]


def _security_event_types(event_type: str) -> list[str]:
    if event_type.endswith(
        (
            ".failed",
            ".denied",
            ".rate_limited",
            ".blocked",
            ".capacity_limited",
            ".rejected",
        )
    ):
        return ["denied"]
    if event_type.endswith((".created", ".consumed")):
        return ["creation"]
    if event_type.endswith(
        (".deleted", ".revoked", ".locked", ".idle_timeout", ".invalidated")
    ):
        return ["deletion"]
    return ["change"]


def _security_event_severity(event_type: str, outcome: str) -> int:
    if event_type.endswith((".rate_limited", ".blocked", ".capacity_limited")):
        return 7
    if event_type.endswith((".deleted", ".revoked")):
        return 6
    if outcome == "failure":
        return 5
    return 2


def _safe_security_attributes(attributes: dict[str, Any] | None) -> dict[str, Any]:
    source = attributes or {}
    safe: dict[str, Any] = {}
    for source_name, target_name in _SECURITY_INTEGER_ATTRIBUTES.items():
        value = source.get(source_name)
        if isinstance(value, bool):
            continue
        if isinstance(value, int) and value >= 0:
            safe[target_name] = value
    for source_name, target_name in _SECURITY_BOOLEAN_ATTRIBUTES.items():
        value = source.get(source_name)
        if isinstance(value, bool):
            safe[target_name] = value
    for source_name, target_name in _SECURITY_KEYWORD_ATTRIBUTES.items():
        value = _safe_keyword(source.get(source_name))
        if value:
            safe[target_name] = value
    return safe


def build_operation_event(
    event_type: str,
    *,
    service_version: str,
    successful: bool = True,
    automatic: bool | None = None,
    reason: str = "",
    size_bytes: int | None = None,
    signature_status: str = "",
) -> dict[str, Any]:
    safe_type = _safe_event_type(event_type, "operation.event")
    outcome = "success" if successful else "failure"
    event_types = ["start"] if safe_type == "service.started" else ["creation"]
    if not successful:
        event_types = ["error"]

    event: dict[str, Any] = {
        "@timestamp": _event_timestamp(),
        "event": {
            "action": safe_type,
            "category": ["process"] if safe_type == "service.started" else ["database"],
            "dataset": "openirn.operations",
            "kind": "event",
            "outcome": outcome,
            "provider": "openirn-api",
            "type": event_types,
        },
        "message": f"OpenIRN operation: {safe_type}",
        "service": {
            "name": "openirn-api",
            "type": "openirn",
            "version": service_version,
        },
    }

    operation: dict[str, Any] = {}
    if isinstance(automatic, bool):
        operation["automatic"] = automatic
    safe_reason = _safe_keyword(reason)
    if safe_reason:
        operation["reason"] = safe_reason
    if isinstance(size_bytes, int) and size_bytes >= 0:
        operation["size_bytes"] = size_bytes
    safe_signature_status = _safe_keyword(signature_status)
    if safe_signature_status:
        operation["signature_status"] = safe_signature_status
    if operation:
        event["openirn"] = {"operation": operation}
    return event


def build_security_event(
    event_type: str,
    *,
    service_version: str,
    timestamp: str = "",
    trace_id: str = "",
    tenant_id: str = "",
    target_tenant_id: str = "",
    actor_user_id: str = "",
    target_user_id: str = "",
    device_id: str = "",
    session_id: str = "",
    enrollment_id: str = "",
    request_id: str = "",
    source_address: str = "",
    successful: bool | None = None,
    reason: str = "",
    attributes: dict[str, Any] | None = None,
) -> dict[str, Any]:
    safe_type = _safe_event_type(event_type)
    if successful is None:
        outcome = (
            "failure"
            if safe_type.endswith(
                (
                    ".failed",
                    ".denied",
                    ".rate_limited",
                    ".blocked",
                    ".capacity_limited",
                    ".rejected",
                )
            )
            else "success"
        )
    else:
        outcome = "success" if successful else "failure"

    event: dict[str, Any] = {
        "@timestamp": str(timestamp or "").strip()[:40] or _event_timestamp(),
        "event": {
            "action": safe_type,
            "category": _security_event_category(safe_type),
            "code": safe_type,
            "dataset": "openirn.security",
            "kind": "event",
            "outcome": outcome,
            "provider": "openirn-api",
            "severity": _security_event_severity(safe_type, outcome),
            "type": _security_event_types(safe_type),
        },
        "message": f"OpenIRN security event: {safe_type}",
        "service": {
            "name": "openirn-api",
            "type": "openirn",
            "version": service_version,
        },
    }

    effective_trace_id = str(trace_id or current_trace_id()).strip().lower()
    if re.fullmatch(r"[0-9a-f]{32}", effective_trace_id):
        event["trace"] = {"id": effective_trace_id}

    tenant_hash = _pseudonymize_identity("tenant", tenant_id)
    if tenant_hash:
        event["organization"] = {"id": tenant_hash}

    actor_hash = _pseudonymize_identity("user", actor_user_id)
    target_user_hash = _pseudonymize_identity("user", target_user_id)
    if actor_hash or target_user_hash:
        event["user"] = {"id": actor_hash or target_user_hash}
        if target_user_hash and target_user_hash != actor_hash:
            event["user"]["target"] = {"id": target_user_hash}

    device_hash = _pseudonymize_identity("device", device_id)
    if device_hash:
        event["device"] = {"id": device_hash}

    session_hash = _pseudonymize_identity("session", session_id)
    if session_hash:
        event["session"] = {"id": session_hash}

    security_fields: dict[str, Any] = {}
    pseudonymous_fields = {
        "enrollment_hash": _pseudonymize_identity("enrollment", enrollment_id),
        "request_hash": _pseudonymize_identity("request", request_id),
        "source_address_hash": _pseudonymize_identity("source_address", source_address),
        "target_tenant_hash": _pseudonymize_identity("tenant", target_tenant_id),
    }
    security_fields.update(
        {name: value for name, value in pseudonymous_fields.items() if value}
    )
    safe_reason = _safe_keyword(reason, "other" if reason else "")
    if safe_reason:
        security_fields["reason"] = safe_reason
    safe_attributes = _safe_security_attributes(attributes)
    if safe_attributes:
        security_fields["attributes"] = safe_attributes
    if security_fields:
        event["openirn"] = {"security": security_fields}

    return event


def _route_pattern(scope: dict[str, Any]) -> str:
    """Return a route template and never a client-controlled raw path."""
    route = scope.get("route")
    path = getattr(route, "path", None)
    if isinstance(path, str) and path.startswith("/"):
        return path

    # Request-limiting middleware can return before FastAPI has selected a route.
    # Resolve the template only in that fallback case; never retain the raw path.
    application = scope.get("app")
    router = getattr(application, "router", None)
    partial_path = None
    for candidate in getattr(router, "routes", ()):
        try:
            match, _ = candidate.matches(scope)
        except (AttributeError, KeyError, TypeError, ValueError):
            continue
        candidate_path = getattr(candidate, "path", None)
        if not isinstance(candidate_path, str) or not candidate_path.startswith("/"):
            continue
        match_name = getattr(match, "name", str(match)).upper()
        if match_name == "FULL":
            return candidate_path
        if match_name == "PARTIAL" and partial_path is None:
            partial_path = candidate_path
    return partial_path or UNMATCHED_ROUTE


def _event_timestamp() -> str:
    return (
        datetime.now(timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )


def _response_headers_with_request_id(
    message: dict[str, Any], request_id: str
) -> dict[str, Any]:
    headers = list(message.get("headers") or [])
    if not any(key.lower() == b"x-request-id" for key, _ in headers):
        headers.append((b"x-request-id", request_id.encode("ascii")))
    return {**message, "headers": headers}


class ApiAccessLogMiddleware:
    """Emit one privacy-preserving ECS/NDJSON event for every HTTP request."""

    def __init__(
        self,
        application: Callable[..., Awaitable[None]],
        service_version: str,
        emit: EventEmitter | None = None,
    ) -> None:
        self.application = application
        self.service_version = service_version
        self.emit = emit or emit_access_event

    async def __call__(
        self,
        scope: dict[str, Any],
        receive: Callable[[], Awaitable[dict[str, Any]]],
        send: Callable[[dict[str, Any]], Awaitable[None]],
    ) -> None:
        if scope.get("type") != "http":
            await self.application(scope, receive, send)
            return

        started_at = time.perf_counter_ns()
        request_id = uuid.uuid4().hex
        state = scope.setdefault("state", {})
        if isinstance(state, dict):
            state["request_id"] = request_id
        trace_token = _REQUEST_TRACE_ID.set(request_id)
        status_code = 500
        response_bytes = 0
        error_type: str | None = None
        emitted = False

        def emit_once() -> None:
            nonlocal emitted
            if emitted:
                return
            emitted = True
            route = _route_pattern(scope)
            duration = max(1, time.perf_counter_ns() - started_at)
            method = str(scope.get("method") or "UNKNOWN").upper()
            event: dict[str, Any] = {
                "@timestamp": _event_timestamp(),
                "event": {
                    "action": f"{method} {route}",
                    "category": ["web"],
                    "dataset": "openirn.api",
                    "duration": duration,
                    "kind": "event",
                    "outcome": "success" if status_code < 400 else "failure",
                    "type": ["access"],
                },
                "http": {
                    "request": {"method": method},
                    "response": {
                        "body": {"bytes": response_bytes},
                        "status_code": status_code,
                    },
                    "version": str(scope.get("http_version") or ""),
                },
                "message": f"{method} {route} {status_code}",
                "device": {"id": ""},
                "openirn": {
                    "client": {
                        "auth_mode": "",
                        "platform": "",
                    }
                },
                "organization": {"id": ""},
                "service": {
                    "name": "openirn-api",
                    "type": "openirn",
                    "version": self.service_version,
                },
                "trace": {"id": request_id},
                "url": {"path": route},
            }
            if error_type:
                event["error"] = {"type": error_type}
            auth_context = state.get("openirn_auth_context")
            if isinstance(auth_context, dict):
                tenant_hash = _pseudonymize_identity(
                    "tenant", auth_context.get("tenantId")
                )
                device_hash = _pseudonymize_identity(
                    "device", auth_context.get("deviceId")
                )
                platform = _safe_keyword(auth_context.get("devicePlatform"))
                auth_mode = _safe_keyword(auth_context.get("authMode"))
                if tenant_hash:
                    event["organization"] = {"id": tenant_hash}
                if device_hash:
                    event["device"] = {"id": device_hash}
                client_fields = {
                    key: value
                    for key, value in {
                        "auth_mode": auth_mode,
                        "platform": platform,
                    }.items()
                    if value
                }
                if client_fields:
                    event["openirn"] = {"client": client_fields}
            try:
                self.emit(event)
            except Exception:
                logging.getLogger(__name__).exception(
                    "Impossible d'écrire l'événement d'accès OpenIRN"
                )

        async def send_with_observability(message: dict[str, Any]) -> None:
            nonlocal response_bytes, status_code
            message_type = message.get("type")
            if message_type == "http.response.start":
                status_code = int(message.get("status") or 500)
                message = _response_headers_with_request_id(message, request_id)
            elif message_type == "http.response.body":
                response_bytes += len(message.get("body") or b"")

            await send(message)
            if message_type == "http.response.body" and not message.get(
                "more_body", False
            ):
                emit_once()

        try:
            await self.application(scope, receive, send_with_observability)
        except BaseException as exc:
            error_type = type(exc).__name__
            status_code = 500 if status_code < 400 else status_code
            emit_once()
            raise
        finally:
            emit_once()
            _REQUEST_TRACE_ID.reset(trace_token)
