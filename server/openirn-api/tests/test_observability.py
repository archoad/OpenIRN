from __future__ import annotations

import json
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

APP_DIR = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP_DIR))

import observability  # noqa: E402


class _Route:
    path = "/campaigns/{campaign_id}"


def _scope(path: str = "/campaigns/secret-campaign") -> dict[str, object]:
    return {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": "GET",
        "scheme": "https",
        "path": path,
        "raw_path": path.encode("utf-8"),
        "query_string": b"pin=1234&token=secret-token",
        "root_path": "",
        "headers": [
            (b"authorization", b"Bearer secret-token"),
            (b"user-agent", b"private-user-agent"),
        ],
        "client": ("192.0.2.10", 54321),
        "server": ("testserver", 443),
    }


async def _receive() -> dict[str, object]:
    return {"type": "http.request", "body": b'{"pin":"1234"}', "more_body": False}


class ApiAccessLogMiddlewareTests(unittest.IsolatedAsyncioTestCase):
    async def test_success_event_uses_route_template_and_adds_request_id(self):
        events: list[dict[str, object]] = []
        sent: list[dict[str, object]] = []

        async def application(scope, receive, send):
            scope["route"] = _Route()
            await receive()
            await send({"type": "http.response.start", "status": 200, "headers": []})
            await send({"type": "http.response.body", "body": b"hello"})

        async def send(message):
            sent.append(message)

        middleware = observability.ApiAccessLogMiddleware(
            application,
            service_version="test-version",
            emit=events.append,
        )
        await middleware(_scope(), _receive, send)

        self.assertEqual(len(events), 1)
        event = events[0]
        self.assertEqual(event["url"]["path"], "/campaigns/{campaign_id}")
        self.assertEqual(event["http"]["response"]["status_code"], 200)
        self.assertEqual(event["http"]["response"]["body"]["bytes"], 5)
        self.assertGreater(event["event"]["duration"], 0)
        self.assertEqual(event["event"]["outcome"], "success")
        self.assertEqual(event["service"]["version"], "test-version")
        self.assertEqual(event["device"], {"id": ""})
        self.assertEqual(event["organization"], {"id": ""})
        self.assertEqual(
            event["openirn"],
            {"client": {"auth_mode": "", "platform": ""}},
        )
        self.assertNotIn("data_stream", event)

        headers = dict(sent[0]["headers"])
        self.assertRegex(headers[b"x-request-id"].decode("ascii"), r"^[0-9a-f]{32}$")
        self.assertEqual(event["trace"]["id"], headers[b"x-request-id"].decode("ascii"))

        serialized = json.dumps(event)
        for secret in (
            "secret-campaign",
            "secret-token",
            "pin=1234",
            "private-user-agent",
            "192.0.2.10",
        ):
            self.assertNotIn(secret, serialized)

    async def test_unknown_path_is_not_retained(self):
        events: list[dict[str, object]] = []

        async def application(scope, receive, send):
            await send({"type": "http.response.start", "status": 404, "headers": []})
            await send({"type": "http.response.body", "body": b"not found"})

        async def send(message):
            return None

        middleware = observability.ApiAccessLogMiddleware(
            application,
            service_version="test-version",
            emit=events.append,
        )
        await middleware(_scope("/unknown/secret-value"), _receive, send)

        self.assertEqual(events[0]["url"]["path"], observability.UNMATCHED_ROUTE)
        self.assertNotIn("secret-value", json.dumps(events[0]))

    async def test_authenticated_usage_contains_only_pseudonyms_and_safe_platform(self):
        events: list[dict[str, object]] = []

        async def application(scope, receive, send):
            scope["route"] = _Route()
            scope["state"]["openirn_auth_context"] = {
                "authMode": "session",
                "tenantId": "tenant-private",
                "deviceId": "device-private",
                "devicePlatform": "windows",
            }
            await send({"type": "http.response.start", "status": 200, "headers": []})
            await send({"type": "http.response.body", "body": b"ok"})

        async def send(message):
            return None

        middleware = observability.ApiAccessLogMiddleware(
            application,
            service_version="test-version",
            emit=events.append,
        )
        with patch.dict(
            os.environ,
            {observability.OBSERVABILITY_HASH_SECRET_ENV: "test-observability-secret-0123456789"},
        ):
            await middleware(_scope(), _receive, send)

        event = events[0]
        serialized = json.dumps(event)
        self.assertNotIn("tenant-private", serialized)
        self.assertNotIn("device-private", serialized)
        self.assertEqual(event["openirn"]["client"]["platform"], "windows")
        self.assertEqual(event["openirn"]["client"]["auth_mode"], "session")
        self.assertRegex(event["organization"]["id"], r"^[0-9a-f]{64}$")
        self.assertRegex(event["device"]["id"], r"^[0-9a-f]{64}$")

    async def test_streamed_response_is_logged_once_after_its_last_chunk(self):
        events: list[dict[str, object]] = []

        async def application(scope, receive, send):
            scope["route"] = _Route()
            await send({"type": "http.response.start", "status": 200, "headers": []})
            await send(
                {
                    "type": "http.response.body",
                    "body": b"first",
                    "more_body": True,
                }
            )
            self.assertEqual(events, [])
            await send({"type": "http.response.body", "body": b"second"})

        async def send(message):
            return None

        middleware = observability.ApiAccessLogMiddleware(
            application,
            service_version="test-version",
            emit=events.append,
        )
        await middleware(_scope(), _receive, send)

        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["http"]["response"]["body"]["bytes"], 11)

    async def test_exception_is_logged_without_its_message(self):
        events: list[dict[str, object]] = []

        async def application(scope, receive, send):
            scope["route"] = _Route()
            raise RuntimeError("PIN 1234 must never be logged")

        async def send(message):
            return None

        middleware = observability.ApiAccessLogMiddleware(
            application,
            service_version="test-version",
            emit=events.append,
        )
        with self.assertRaisesRegex(RuntimeError, "must never be logged"):
            await middleware(_scope(), _receive, send)

        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["http"]["response"]["status_code"], 500)
        self.assertEqual(events[0]["event"]["outcome"], "failure")
        self.assertEqual(events[0]["error"], {"type": "RuntimeError"})
        self.assertNotIn("1234", json.dumps(events[0]))

    def test_default_emitter_outputs_one_valid_ndjson_line(self):
        logger = Mock()
        with patch.object(observability, "_access_logger", return_value=logger):
            observability.emit_access_event(
                {
                    "@timestamp": "2026-08-29T00:00:00.000Z",
                    "event": {"dataset": "openirn.api"},
                }
            )

        logger.info.assert_called_once()
        line = logger.info.call_args.args[0]
        self.assertNotIn("\n", line)
        self.assertEqual(json.loads(line)["event"]["dataset"], "openirn.api")


class OperationEventTests(unittest.TestCase):
    def test_backup_event_contains_only_bounded_operational_fields(self):
        event = observability.build_operation_event(
            "backup.created",
            service_version="test-version",
            automatic=True,
            reason="scheduled",
            size_bytes=4096,
            signature_status="valid",
        )

        self.assertEqual(event["event"]["dataset"], "openirn.operations")
        self.assertEqual(event["event"]["outcome"], "success")
        self.assertEqual(event["service"]["version"], "test-version")
        self.assertEqual(
            event["openirn"]["operation"],
            {
                "automatic": True,
                "reason": "scheduled",
                "signature_status": "valid",
                "size_bytes": 4096,
            },
        )

    def test_failed_operation_does_not_retain_exception_message(self):
        event = observability.build_operation_event(
            "backup.failed",
            service_version="test-version",
            successful=False,
            reason="RuntimeError: password=private",
        )

        serialized = json.dumps(event)
        self.assertEqual(event["event"]["outcome"], "failure")
        self.assertNotIn("password", serialized)
        self.assertNotIn("private", serialized)

    def test_invalid_operation_action_uses_operation_fallback(self):
        event = observability.build_operation_event(
            "invalid operation with spaces",
            service_version="test-version",
        )

        self.assertEqual(event["event"]["action"], "operation.event")


if __name__ == "__main__":
    unittest.main()
