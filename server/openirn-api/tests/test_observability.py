from __future__ import annotations

import json
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


if __name__ == "__main__":
    unittest.main()
