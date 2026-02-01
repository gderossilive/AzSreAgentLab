#!/usr/bin/env python3
import json
import os
import time
import urllib.parse
import urllib.request
import urllib.error
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ingestion_url = os.environ.get("INGESTION_URL", "").strip()
# For managed identity (App Service-style), the token request uses a *resource* (not scope).
token_resource = os.environ.get("TOKEN_RESOURCE", "https://monitor.azure.com/").strip()
managed_identity_client_id = os.environ.get("AZURE_CLIENT_ID", "").strip()

identity_endpoint = os.environ.get("IDENTITY_ENDPOINT", "").strip()
identity_header = os.environ.get("IDENTITY_HEADER", "").strip()

_listen_host = os.environ.get("LISTEN_HOST", "0.0.0.0")
_listen_port = int(os.environ.get("LISTEN_PORT", "8081"))

_token_cache = {
    "access_token": None,
    "expires_at": 0,
}


def _now() -> int:
    return int(time.time())


def _parse_expires_on(expires_on_value) -> int:
    # App Service MSI often returns expires_on as a unix epoch string.
    try:
        return int(expires_on_value)
    except Exception:
        return _now() + 300


def _get_managed_identity_token() -> str:
    if not identity_endpoint or not identity_header:
        raise RuntimeError(
            "Managed identity env vars missing. Expected IDENTITY_ENDPOINT and IDENTITY_HEADER. "
            "Ensure the Container App has a managed identity assigned."
        )

    # Cache with a 2-minute safety margin.
    if _token_cache["access_token"] and _token_cache["expires_at"] > (_now() + 120):
        return _token_cache["access_token"]

    query = {
        "api-version": "2019-08-01",
        "resource": token_resource,
    }
    if managed_identity_client_id:
        # User-assigned identity (optional)
        query["client_id"] = managed_identity_client_id

    url = identity_endpoint + ("&" if "?" in identity_endpoint else "?") + urllib.parse.urlencode(query)

    req = urllib.request.Request(
        url,
        method="GET",
        headers={
            "X-IDENTITY-HEADER": identity_header,
        },
    )

    with urllib.request.urlopen(req, timeout=10) as resp:
        body = resp.read()

    payload = json.loads(body.decode("utf-8"))
    access_token = payload.get("access_token")
    if not access_token:
        raise RuntimeError(f"Managed identity token response missing access_token: {payload}")

    expires_at = _parse_expires_on(payload.get("expires_on"))
    _token_cache["access_token"] = access_token
    _token_cache["expires_at"] = expires_at
    return access_token


def _forward_to_ingestion(headers: dict, body: bytes) -> tuple[int, bytes]:
    if not ingestion_url:
        raise RuntimeError("INGESTION_URL is not set")

    access_token = _get_managed_identity_token()

    forward_headers = {
        # Required
        "Authorization": f"Bearer {access_token}",
        "Content-Type": headers.get("Content-Type", "application/x-protobuf"),
        # Prometheus remote_write commonly uses snappy; preserve if present.
        "Content-Encoding": headers.get("Content-Encoding", ""),
        "User-Agent": "grocery-prom-remote-write-proxy/1.0",
    }

    # Remove empty headers
    forward_headers = {k: v for k, v in forward_headers.items() if v}

    req = urllib.request.Request(
        ingestion_url,
        data=body,
        method="POST",
        headers=forward_headers,
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read() or str(e).encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    def _send(self, status: int, body: bytes, content_type: str = "text/plain; charset=utf-8"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/", "/health", "/healthz", "/ready", "/readyz"):
            self._send(HTTPStatus.OK, b"ok")
            return
        self._send(HTTPStatus.NOT_FOUND, b"not found")

    def do_POST(self):
        if self.path not in ("/api/v1/write", "/write"):
            self._send(HTTPStatus.NOT_FOUND, b"not found")
            return

        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length > 0 else b""

        try:
            status, resp_body = _forward_to_ingestion(dict(self.headers), body)
        except Exception as e:
            self._send(HTTPStatus.INTERNAL_SERVER_ERROR, str(e).encode("utf-8"))
            return

        # Prometheus expects 2xx for success.
        if 200 <= status < 300:
            self._send(HTTPStatus.NO_CONTENT, b"")
        else:
            self._send(HTTPStatus.BAD_GATEWAY, resp_body)

    def log_message(self, format, *args):
        # Keep default logging minimal (stdout only)
        super().log_message(format, *args)


def main():
    if not ingestion_url:
        raise SystemExit("INGESTION_URL must be set")

    server = ThreadingHTTPServer((_listen_host, _listen_port), Handler)
    print(f"Listening on http://{_listen_host}:{_listen_port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
