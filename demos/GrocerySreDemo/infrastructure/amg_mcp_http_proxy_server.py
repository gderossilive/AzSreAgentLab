import asyncio
import contextlib
import json
import os
import select
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any, Literal, Optional

from mcp.server.fastmcp import FastMCP
from mcp.server.fastmcp.server import StreamableHTTPASGIApp
from starlette.applications import Starlette
from starlette.routing import Route
from starlette.requests import ClientDisconnect, Request
from starlette.responses import JSONResponse, Response
import uvicorn


@dataclass
class JsonRpcResponse:
    raw: dict[str, Any]

    @property
    def is_error(self) -> bool:
        return "error" in self.raw


class McpStdioClient:
    def __init__(self, argv: list[str]):
        self._proc = subprocess.Popen(
            argv,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=False,
            bufsize=0,
        )
        assert self._proc.stdin and self._proc.stdout
        self._stdin = self._proc.stdin
        self._stdout = self._proc.stdout
        self._stdout_fd = self._proc.stdout.fileno()
        self._recv_buf = b""

        # Enforce timeouts reliably: avoid blocking reads on pipes.
        try:
            os.set_blocking(self._stdout_fd, False)
        except Exception:
            # Best-effort; timeouts may be less strict if the runtime disallows this.
            pass

        self._lock = threading.Lock()

        if self._proc.stderr:
            self._stderr = self._proc.stderr

            def _pump_stderr() -> None:
                try:
                    for line in iter(self._stderr.readline, b""):
                        try:
                            decoded = line.decode("utf-8", errors="replace")
                        except Exception:
                            decoded = repr(line)
                        sys.stderr.write("[amg-mcp] " + decoded)
                        sys.stderr.flush()
                except Exception as exc:
                    sys.stderr.write(f"[amg-mcp] <stderr pump error: {exc}>\n")
                    sys.stderr.flush()

            threading.Thread(target=_pump_stderr, daemon=True).start()

    def close(self) -> None:
        try:
            if self._proc.stdin:
                self._proc.stdin.close()
        except Exception:
            pass
        try:
            self._proc.terminate()
        except Exception:
            pass

    def _send(self, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        header = f"Content-Length: {len(body)}\r\n\r\n".encode("ascii")
        self._stdin.write(header)
        self._stdin.write(body)
        self._stdin.flush()

    def notify(self, method: str, params: dict[str, Any]) -> None:
        with self._lock:
            self._send({"jsonrpc": "2.0", "method": method, "params": params})

    def _read_message(self, timeout_s: float = 30.0) -> dict[str, Any]:
        # Minimal LSP-style framing: headers until \r\n\r\n then JSON body.
        start = time.time()
        buf = self._recv_buf
        def _find_header_end(data: bytes) -> tuple[int, int]:
            # Prefer CRLF framing, but accept LF-only framing as well.
            idx = data.find(b"\r\n\r\n")
            if idx >= 0:
                return idx, 4
            idx = data.find(b"\n\n")
            if idx >= 0:
                return idx, 2
            return -1, 0

        header_end, sep_len = _find_header_end(buf)
        while header_end < 0:
            remaining = timeout_s - (time.time() - start)
            if remaining <= 0:
                raise TimeoutError("Timed out waiting for MCP headers")

            r, _, _ = select.select([self._stdout_fd], [], [], remaining)
            if not r:
                raise TimeoutError("Timed out waiting for MCP headers")

            chunk = os.read(self._stdout_fd, 4096)
            if not chunk:
                rc = self._proc.poll()
                raise RuntimeError(f"MCP server stdout closed (returncode={rc})")
            buf += chunk

            header_end, sep_len = _find_header_end(buf)

        header_blob = buf[:header_end]
        rest = buf[header_end + sep_len :]
        content_length: Optional[int] = None
        normalized = header_blob.replace(b"\r\n", b"\n")
        for line in normalized.split(b"\n"):
            if line.lower().startswith(b"content-length:"):
                content_length = int(line.split(b":", 1)[1].strip())
                break
        if content_length is None:
            raise ValueError(f"Missing Content-Length header: {header_blob!r}")

        while len(rest) < content_length:
            remaining = timeout_s - (time.time() - start)
            if remaining <= 0:
                raise TimeoutError("Timed out waiting for MCP body")

            r, _, _ = select.select([self._stdout_fd], [], [], remaining)
            if not r:
                raise TimeoutError("Timed out waiting for MCP body")

            chunk = os.read(self._stdout_fd, max(1, content_length - len(rest)))
            if not chunk:
                rc = self._proc.poll()
                raise RuntimeError(f"MCP server stdout closed while reading body (returncode={rc})")
            rest += chunk

        body_bytes = rest[:content_length]
        self._recv_buf = rest[content_length:]

        return json.loads(body_bytes.decode("utf-8"))

    def request(self, method: str, params: dict[str, Any], req_id: int, timeout_s: float = 60.0) -> JsonRpcResponse:
        with self._lock:
            self._send({"jsonrpc": "2.0", "id": req_id, "method": method, "params": params})

            start = time.time()
            while True:
                if time.time() - start > timeout_s:
                    raise TimeoutError(f"Timed out waiting for response to {method}")

                msg = self._read_message(timeout_s=timeout_s)

                # Ignore notifications/other IDs.
                if msg.get("id") == req_id:
                    return JsonRpcResponse(raw=msg)


def _env_str(name: str, default: str = "") -> str:
    value = os.getenv(name)
    return default if value is None or value == "" else value


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None or raw.strip() == "":
        return default
    try:
        return int(raw.strip())
    except Exception:
        return default


def _schema_properties(tools_list_resp: dict[str, Any], tool_name: str) -> set[str]:
    result = tools_list_resp.get("result") or {}
    tools = result.get("tools")
    if not isinstance(tools, list):
        return set()
    for tool in tools:
        if tool.get("name") == tool_name:
            schema = tool.get("inputSchema")
            if isinstance(schema, dict):
                props = schema.get("properties")
                if isinstance(props, dict):
                    return set(props.keys())
    return set()


class AmgMcpBackend:
    def __init__(self, grafana_endpoint: str):
        self._next_id = 1
        argv = [
            "/usr/local/bin/amg-mcp",
            "--AmgMcpOptions:Transport=Stdio",
            f"--AmgMcpOptions:AzureManagedGrafanaEndpoint={grafana_endpoint}",
        ]
        self._client = McpStdioClient(argv)

        # Compatibility note: the amg-mcp CLI server may not accept newer MCP
        # initialize params (protocolVersion/clientInfo) and can hang without
        # emitting framed output. Keep this payload minimal.
        init = self._call(
            "initialize",
            {"capabilities": {}},
            timeout_s=float(_env_int("AMG_MCP_INIT_TIMEOUT_S", 20)),
        )
        if init.is_error:
            raise RuntimeError(f"amg-mcp initialize failed: {init.raw.get('error')}")

        # Some MCP/stdio servers expect an LSP-style initialized notification
        # before they start answering tool calls.
        try:
            self._client.notify("initialized", {})
            self._client.notify("notifications/initialized", {})
        except Exception:
            pass

        tools = self._call("tools/list", {}, timeout_s=float(_env_int("AMG_MCP_TOOLS_LIST_TIMEOUT_S", 30)))
        if tools.is_error:
            raise RuntimeError(f"amg-mcp tools/list failed: {tools.raw.get('error')}")

        # Cache backend tool schemas so we can safely filter forwarded arguments
        # (the underlying tool parameter names may vary by version).
        self._tool_supported_keys: dict[str, set[str]] = {}
        for tool_name in (
            "amgmcp_datasource_list",
            "amgmcp_query_datasource",
            "amgmcp_dashboard_search",
            "amgmcp_query_resource_log",
            "amgmcp_query_resource_graph",
            "amgmcp_query_azure_subscriptions",
            "amgmcp_image_render",
        ):
            self._tool_supported_keys[tool_name] = _schema_properties(tools.raw, tool_name)

    def close(self) -> None:
        self._client.close()

    def _call(self, method: str, params: dict[str, Any], timeout_s: float = 60.0) -> JsonRpcResponse:
        req_id = self._next_id
        self._next_id += 1
        return self._client.request(method, params, req_id=req_id, timeout_s=timeout_s)

    def tool_call(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        supported_keys = self._tool_supported_keys.get(name)
        if supported_keys:
            arguments = {k: v for k, v in arguments.items() if k in supported_keys}

        resp = self._call(
            "tools/call",
            {"name": name, "arguments": arguments},
            # Keep this below common MCP client timeouts (~100s).
            timeout_s=float(_env_int("AMG_MCP_TOOL_TIMEOUT_S", 90)),
        )
        return resp.raw


def _grafana_aad_resource() -> str:
    # Default resource for Azure Managed Grafana data-plane API.
    # (Managed Identity endpoint uses `resource=...`, not OAuth scopes.)
    return _env_str("GRAFANA_AAD_RESOURCE", "https://grafana.azure.com")


def _grafana_http_timeout_s() -> float:
    return float(_env_int("GRAFANA_HTTP_TIMEOUT_S", 20))


def _loki_http_timeout_s() -> float:
    return float(_env_int("LOKI_HTTP_TIMEOUT_S", 15))


def _loki_endpoint() -> str:
    return _env_str("LOKI_ENDPOINT").rstrip("/")


def _looks_like_loki_datasource(name: Optional[str]) -> bool:
    if not name:
        return False
    return "loki" in name.strip().lower()


def _loki_query_range(*, query: str, start_ms: int, end_ms: int, limit: Optional[int]) -> dict[str, Any]:
    endpoint = _loki_endpoint()
    if not endpoint:
        raise RuntimeError("LOKI_ENDPOINT is not set")

    # Loki expects nanoseconds since epoch.
    params: dict[str, str] = {
        "query": query,
        "start": str(int(start_ms) * 1_000_000),
        "end": str(int(end_ms) * 1_000_000),
    }
    if limit is not None:
        params["limit"] = str(int(limit))

    # Support either a bare base URL (https://host) or a base that already includes /loki.
    base = endpoint
    if base.endswith("/loki"):
        url = base + "/api/v1/query_range"
    else:
        url = base + "/loki/api/v1/query_range"

    url = url + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, method="GET", headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=_loki_http_timeout_s()) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    return payload


def _get_managed_identity_access_token(resource: str) -> str:
    endpoint = _env_str("IDENTITY_ENDPOINT").strip()
    secret = _env_str("IDENTITY_HEADER").strip()
    if not endpoint or not secret:
        raise RuntimeError("Managed identity endpoint not available (IDENTITY_ENDPOINT/IDENTITY_HEADER missing)")

    params: dict[str, str] = {
        "api-version": "2019-08-01",
        "resource": resource,
    }
    client_id = _env_str("AZURE_CLIENT_ID").strip()
    if client_id:
        # Needed for user-assigned managed identity.
        params["client_id"] = client_id

    join_char = "&" if "?" in endpoint else "?"
    url = endpoint + join_char + urllib.parse.urlencode(params)
    req = urllib.request.Request(
        url,
        method="GET",
        headers={
            "X-IDENTITY-HEADER": secret,
            # Some MSI endpoints require Metadata=true.
            "Metadata": "true",
        },
    )
    with urllib.request.urlopen(req, timeout=_grafana_http_timeout_s()) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    token = payload.get("access_token")
    if not token:
        raise RuntimeError(f"Managed identity token response missing access_token: keys={list(payload.keys())}")
    return token


def _grafana_get_json(path: str) -> Any:
    endpoint = _env_str("GRAFANA_ENDPOINT").rstrip("/")
    if not endpoint:
        raise RuntimeError("GRAFANA_ENDPOINT is required")
    url = endpoint + path

    token = _get_managed_identity_access_token(_grafana_aad_resource())
    req = urllib.request.Request(
        url,
        method="GET",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=_grafana_http_timeout_s()) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _backend_tool_call_safe(name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    try:
        backend = _get_backend()
        return backend.tool_call(name, arguments)
    except TimeoutError as exc:
        return {
            "ok": False,
            "errorType": "TimeoutError",
            "error": str(exc),
            "hint": "The underlying amg-mcp stdio call exceeded the proxy timeout. Try again or increase AMG_MCP_TOOL_TIMEOUT_S (keep it <100s to avoid client cancellation).",
        }
    except Exception as exc:
        return {
            "ok": False,
            "errorType": type(exc).__name__,
            "error": str(exc),
        }


_datasource_cache_lock = threading.Lock()
_datasource_cache_value: Optional[dict[str, Any]] = None
_datasource_cache_at: float = 0.0


def _datasource_cache_ttl_s() -> int:
    # Cache the list briefly to keep investigation workflows snappy and to avoid
    # repeated slow calls causing client-side timeouts.
    return _env_int("DATASOURCE_LIST_CACHE_TTL_S", 300)


def _cached_datasource_list() -> Optional[dict[str, Any]]:
    ttl = _datasource_cache_ttl_s()
    if ttl <= 0:
        return None
    with _datasource_cache_lock:
        if _datasource_cache_value is None:
            return None
        if time.time() - _datasource_cache_at > ttl:
            return None
        return _datasource_cache_value


def _set_cached_datasource_list(value: dict[str, Any]) -> None:
    with _datasource_cache_lock:
        global _datasource_cache_value, _datasource_cache_at
        _datasource_cache_value = value
        _datasource_cache_at = time.time()


_WRITE_TOOLS: set[str] = set()


def _env_bool(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    raw = raw.strip().lower()
    if raw in {"1", "true", "t", "yes", "y", "on"}:
        return True
    if raw in {"0", "false", "f", "no", "n", "off"}:
        return False
    return default


def _require_write_enabled(tool_name: str) -> None:
    if tool_name not in _WRITE_TOOLS:
        return
    if _env_bool("ENABLE_GRAFANA_WRITE_TOOLS", default=False):
        return
    raise PermissionError(
        f"{tool_name} is disabled by default. Set ENABLE_GRAFANA_WRITE_TOOLS=true to enable write-capable Grafana tools."
    )


mcp = FastMCP(
    "amg-mcp-http-proxy",
    host=os.getenv("HOST", "0.0.0.0"),
    port=int(os.getenv("PORT", "8000")),
    # Azure SRE Agent's MCP connector validation appears to behave like a
    # JSON-only client. Enabling JSON-only responses relaxes the streamable HTTP
    # Accept header requirement to just `application/json`.
    json_response=True,
)


@mcp.custom_route("/", methods=["GET"], include_in_schema=False)
async def _root(_: Request) -> Response:
    return JSONResponse({"name": "amg-mcp-http-proxy", "status": "ok"})


@mcp.custom_route("/healthz", methods=["GET"], include_in_schema=False)
async def _healthz(_: Request) -> Response:
    return JSONResponse({"status": "ok"})


def _headers_to_dict(scope_headers: list[tuple[bytes, bytes]]) -> dict[str, str]:
    out: dict[str, str] = {}
    for k, v in scope_headers:
        try:
            key = k.decode("latin-1").lower()
            val = v.decode("latin-1")
        except Exception:
            continue
        out[key] = val
    return out


def _set_header(scope_headers: list[tuple[bytes, bytes]], key: str, value: str) -> list[tuple[bytes, bytes]]:
    key_l = key.lower().encode("latin-1")
    value_b = value.encode("latin-1")
    filtered = [(k, v) for (k, v) in scope_headers if k.lower() != key_l]
    filtered.append((key_l, value_b))
    return filtered


async def _read_body(receive) -> bytes:
    body = b""
    more_body = True
    while more_body:
        message = await receive()
        msg_type = message.get("type")
        if msg_type == "http.disconnect":
            break
        if msg_type != "http.request":
            continue
        body += message.get("body", b"")
        more_body = bool(message.get("more_body"))
    return body


def _make_receive_with_body(body: bytes):
    sent = False

    async def receive():
        nonlocal sent
        if sent:
            return {"type": "http.request", "body": b"", "more_body": False}
        sent = True
        return {"type": "http.request", "body": body, "more_body": False}

    return receive


class _CompatStreamableHTTPApp:
    def __init__(self) -> None:
        # Ensure the session manager exists.
        mcp.streamable_http_app()
        self._inner = StreamableHTTPASGIApp(mcp.session_manager)

    async def __call__(self, scope, receive, send) -> None:
        if scope.get("type") != "http":
            await self._inner(scope, receive, send)
            return

        method = (scope.get("method") or "").upper()
        path = scope.get("path") or ""

        # Basic request logging for debugging connector behavior.
        try:
            headers = _headers_to_dict(list(scope.get("headers") or []))
            accept = headers.get("accept", "")
            content_type = headers.get("content-type", "")
            sys.stderr.write(f"[proxy] {method} {path} accept={accept!r} content-type={content_type!r}\n")
            sys.stderr.flush()
        except Exception:
            pass

        # For JSON-only clients/connectors that omit Accept, inject a reasonable default.
        try:
            headers_list: list[tuple[bytes, bytes]] = list(scope.get("headers") or [])
            headers_map = _headers_to_dict(headers_list)
            accept_hdr = headers_map.get("accept")
            if accept_hdr is None or accept_hdr.strip() == "" or accept_hdr.strip() == "*/*":
                # Default Accept based on the method:
                # - POST expects JSON (and in JSON-only mode this is sufficient)
                # - GET expects SSE for the server->client stream
                default_accept = "application/json" if method == "POST" else "text/event-stream"
                scope = {**scope, "headers": _set_header(headers_list, "accept", default_accept)}
        except Exception:
            pass

        # Some validators send a best-effort session cleanup even when they don't
        # track/forward the session id. Returning 200 here prevents a hard failure.
        if method == "DELETE" and path == "/mcp":
            try:
                headers_list = list(scope.get("headers") or [])
                headers_map = _headers_to_dict(headers_list)
                if "mcp-session-id" not in headers_map:
                    body = b"null"
                    await send(
                        {
                            "type": "http.response.start",
                            "status": 200,
                            "headers": [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode("ascii"))],
                        }
                    )
                    await send({"type": "http.response.body", "body": body, "more_body": False})
                    return
            except Exception:
                pass

        # Some validators probe the SSE endpoint without tracking/forwarding the
        # session id. Reply 200 to avoid a hard failure during validation.
        if method == "GET" and path == "/mcp":
            try:
                headers_list = list(scope.get("headers") or [])
                headers_map = _headers_to_dict(headers_list)
                if "mcp-session-id" not in headers_map:
                    accept_hdr = (headers_map.get("accept") or "").lower()
                    if "text/event-stream" in accept_hdr:
                        body = b": ok\n\n"
                        await send(
                            {
                                "type": "http.response.start",
                                "status": 200,
                                "headers": [
                                    (b"content-type", b"text/event-stream"),
                                    (b"cache-control", b"no-cache"),
                                    (b"content-length", str(len(body)).encode("ascii")),
                                ],
                            }
                        )
                        await send({"type": "http.response.body", "body": body, "more_body": False})
                        return

                    body = b"null"
                    await send(
                        {
                            "type": "http.response.start",
                            "status": 200,
                            "headers": [
                                (b"content-type", b"application/json"),
                                (b"content-length", str(len(body)).encode("ascii")),
                            ],
                        }
                    )
                    await send({"type": "http.response.body", "body": body, "more_body": False})
                    return
            except Exception:
                pass

        # Some validators abort mid-request; pre-read the body so the inner MCP
        # handler doesn't raise ClientDisconnect while reading.
        if method == "POST" and path == "/mcp":
            raw: bytes
            try:
                raw = await _read_body(receive)
            except ClientDisconnect:
                raw = b""

            if not raw:
                body = b"null"
                await send(
                    {
                        "type": "http.response.start",
                        "status": 200,
                        "headers": [
                            (b"content-type", b"application/json"),
                            (b"content-length", str(len(body)).encode("ascii")),
                        ],
                    }
                )
                await send({"type": "http.response.body", "body": body, "more_body": False})
                return

            # Some clients send an incomplete initialize payload. Patch defaults.
            try:
                obj = json.loads(raw.decode("utf-8"))
            except Exception:
                body = b"null"
                await send(
                    {
                        "type": "http.response.start",
                        "status": 200,
                        "headers": [
                            (b"content-type", b"application/json"),
                            (b"content-length", str(len(body)).encode("ascii")),
                        ],
                    }
                )
                await send({"type": "http.response.body", "body": body, "more_body": False})
                return

            if isinstance(obj, dict) and obj.get("method") == "initialize":
                params = obj.get("params")
                if not isinstance(params, dict):
                    params = {}
                params.setdefault("protocolVersion", "2025-11-25")
                params.setdefault("capabilities", {})
                params.setdefault("clientInfo", {"name": "azure-sre-agent", "version": ""})
                obj["params"] = params
                raw = json.dumps(obj, separators=(",", ":")).encode("utf-8")

            receive = _make_receive_with_body(raw)

        try:
            await self._inner(scope, receive, send)
        except ClientDisconnect:
            # If the client disconnects mid-body, the portal validator may still
            # issue follow-up teardown requests. Avoid surfacing a hard failure.
            if method == "POST" and path == "/mcp":
                try:
                    body = b"null"
                    await send(
                        {
                            "type": "http.response.start",
                            "status": 200,
                            "headers": [
                                (b"content-type", b"application/json"),
                                (b"content-length", str(len(body)).encode("ascii")),
                            ],
                        }
                    )
                    await send({"type": "http.response.body", "body": body, "more_body": False})
                except Exception:
                    pass
                return
            raise


_mcp_streamable_http = _CompatStreamableHTTPApp()


@contextlib.asynccontextmanager
async def _lifespan(_: Starlette):
    async with mcp.session_manager.run():
        yield


async def _root_starlette(req: Request) -> Response:
    return await _root(req)


async def _healthz_starlette(req: Request) -> Response:
    return await _healthz(req)


app = Starlette(
    debug=False,
    lifespan=_lifespan,
    routes=[
        Route("/", endpoint=_root_starlette, methods=["GET"]),
        Route("/healthz", endpoint=_healthz_starlette, methods=["GET"]),
        Route("/mcp", endpoint=_mcp_streamable_http, methods=["GET", "POST", "DELETE", "OPTIONS"]),
    ],
)

_backend: Optional[AmgMcpBackend] = None
_backend_lock = threading.Lock()


def _get_backend() -> AmgMcpBackend:
    global _backend
    with _backend_lock:
        if _backend is not None:
            return _backend

        grafana_endpoint = _env_str("GRAFANA_ENDPOINT").rstrip("/")
        if not grafana_endpoint:
            raise RuntimeError("GRAFANA_ENDPOINT is required")

        _backend = AmgMcpBackend(grafana_endpoint=grafana_endpoint)
        return _backend


@mcp.tool()
async def amgmcp_datasource_list() -> dict[str, Any]:
    """List datasources from Azure Managed Grafana using managed identity."""

    cached = await asyncio.to_thread(_cached_datasource_list)
    if cached is not None:
        return cached

    # If Loki direct access is configured, prefer a fast minimal list.
    if _loki_endpoint() and _env_bool("PREFER_LOKI_DIRECT_DATASOURCE_LIST", default=True):
        out = {
            "ok": True,
            "source": "loki-direct",
            "datasources": [
                {
                    "name": "Loki (grocery)",
                    "type": "loki",
                    "url": _loki_endpoint(),
                }
            ],
        }
        await asyncio.to_thread(_set_cached_datasource_list, out)
        return out

    # Prefer the underlying amg-mcp tool.
    # The direct Grafana data-plane API call to /api/datasources can return 401
    # in some Managed Identity setups; relying on amg-mcp keeps behavior stable.
    out = await asyncio.to_thread(_backend_tool_call_safe, "amgmcp_datasource_list", {})

    # Fallback: if the amg-mcp backend stalls and we have a Loki endpoint configured,
    # return a minimal datasource list so callers can proceed.
    if isinstance(out, dict) and out.get("ok") is False and out.get("errorType") == "TimeoutError":
        if _loki_endpoint():
            out = {
                "ok": True,
                "source": "loki-direct",
                "datasources": [
                    {
                        "name": "Loki (grocery)",
                        "type": "loki",
                        "url": _loki_endpoint(),
                    }
                ],
            }
    # Cache successful responses even if they came from the slower path.
    if isinstance(out, dict) and "error" not in out:
        await asyncio.to_thread(_set_cached_datasource_list, out)
    return out


@mcp.tool()
async def amgmcp_query_datasource(
    datasourceUid: Optional[str] = None,
    datasourceUID: Optional[str] = None,
    datasource_uid: Optional[str] = None,
    datasourceName: Optional[str] = None,
    datasourcename: Optional[str] = None,
    query: Optional[str] = None,
    expr: Optional[str] = None,
    limit: Optional[int] = None,
    fromMs: Optional[int] = None,
    toMs: Optional[int] = None,
    fromms: Optional[int] = None,
    toms: Optional[int] = None,
    startTime: Optional[int] = None,
    endTime: Optional[int] = None,
    starttime: Optional[int] = None,
    endtime: Optional[int] = None,
) -> dict[str, Any]:
    """Query a datasource (commonly Loki) via Azure Managed Grafana using managed identity.

    This is a proxy to the underlying `amg-mcp` tool. The backend tool's exact parameter names
    can vary by version; this proxy forwards only supported keys.
    """

    args: dict[str, Any] = {}
    if datasourceUid is not None:
        args["datasourceUid"] = datasourceUid
    if datasourceUID is not None:
        args["datasourceUID"] = datasourceUID
    if datasource_uid is not None:
        args["datasource_uid"] = datasource_uid
    ds_name = datasourceName if datasourceName is not None else datasourcename
    if ds_name is not None:
        args["datasourceName"] = ds_name

    if query is not None:
        args["query"] = query
    if expr is not None:
        args["expr"] = expr

    if limit is not None:
        args["limit"] = limit

    # Time bounds; use whichever keys the backend supports.
    from_ms = fromMs if fromMs is not None else fromms
    to_ms = toMs if toMs is not None else toms
    start_time = startTime if startTime is not None else starttime
    end_time = endTime if endTime is not None else endtime

    if from_ms is not None:
        args["from"] = from_ms
        args["startTime"] = from_ms
    if to_ms is not None:
        args["to"] = to_ms
        args["endTime"] = to_ms
    if start_time is not None:
        args["startTime"] = start_time
    if end_time is not None:
        args["endTime"] = end_time

    # Prefer Loki-direct if the datasource looks like Loki and a direct endpoint is configured.
    if _looks_like_loki_datasource(ds_name) and _loki_endpoint():
        effective_query = query if query is not None else expr
        if not effective_query:
            return {"ok": False, "source": "loki-direct", "errorType": "ValueError", "error": "query is required"}

        start_ms = from_ms if from_ms is not None else start_time
        end_ms = to_ms if to_ms is not None else end_time
        if start_ms is None or end_ms is None:
            return {
                "ok": False,
                "source": "loki-direct",
                "errorType": "ValueError",
                "error": "fromMs/toMs (or startTime/endTime) are required",
            }

        try:
            payload = await asyncio.to_thread(
                _loki_query_range,
                query=str(effective_query),
                start_ms=int(start_ms),
                end_ms=int(end_ms),
                limit=limit,
            )
            return {"ok": True, "source": "loki-direct", "result": payload}
        except Exception as exc:
            return {"ok": False, "source": "loki-direct", "errorType": type(exc).__name__, "error": str(exc)}

    return await asyncio.to_thread(_backend_tool_call_safe, "amgmcp_query_datasource", args)


@mcp.tool()
async def amgmcp_dashboard_search(
    query: Optional[str] = None,
    search: Optional[str] = None,
    arguments: Optional[dict[str, Any]] = None,
) -> dict[str, Any]:
    """Search dashboards in Azure Managed Grafana (managed identity)."""

    args: dict[str, Any] = dict(arguments or {})
    q = query if query is not None else search
    if q is not None:
        args.setdefault("query", q)
        args.setdefault("search", q)

    backend = await asyncio.to_thread(_get_backend)
    return await asyncio.to_thread(backend.tool_call, "amgmcp_dashboard_search", args)


@mcp.tool()
async def amgmcp_query_resource_log(
    query: Optional[str] = None,
    kql: Optional[str] = None,
    resourceId: Optional[str] = None,
    arguments: Optional[dict[str, Any]] = None,
) -> dict[str, Any]:
    """Run KQL against Azure Monitor resource logs via Grafana's Azure Monitor datasource (managed identity)."""

    args: dict[str, Any] = dict(arguments or {})
    q = query if query is not None else kql
    if q is not None:
        args.setdefault("query", q)
        args.setdefault("kql", q)
    if resourceId is not None:
        args.setdefault("resourceId", resourceId)

    backend = await asyncio.to_thread(_get_backend)
    return await asyncio.to_thread(backend.tool_call, "amgmcp_query_resource_log", args)


@mcp.tool()
async def amgmcp_query_resource_graph(
    query: Optional[str] = None,
    kql: Optional[str] = None,
    subscriptions: Optional[list[str]] = None,
    arguments: Optional[dict[str, Any]] = None,
) -> dict[str, Any]:
    """Run an Azure Resource Graph query via Grafana (managed identity)."""

    args: dict[str, Any] = dict(arguments or {})
    q = query if query is not None else kql
    if q is not None:
        args.setdefault("query", q)
        args.setdefault("kql", q)
    if subscriptions is not None:
        args.setdefault("subscriptions", subscriptions)

    backend = await asyncio.to_thread(_get_backend)
    return await asyncio.to_thread(backend.tool_call, "amgmcp_query_resource_graph", args)


@mcp.tool()
async def amgmcp_query_azure_subscriptions(arguments: Optional[dict[str, Any]] = None) -> dict[str, Any]:
    """List subscriptions visible to Grafana's Azure Monitor datasource (managed identity)."""

    args: dict[str, Any] = dict(arguments or {})
    backend = await asyncio.to_thread(_get_backend)
    return await asyncio.to_thread(backend.tool_call, "amgmcp_query_azure_subscriptions", args)


@mcp.tool()
async def amgmcp_image_render(
    dashboardUid: Optional[str] = None,
    uid: Optional[str] = None,
    panelId: Optional[int] = None,
    fromMs: Optional[int] = None,
    toMs: Optional[int] = None,
    width: Optional[int] = None,
    height: Optional[int] = None,
    arguments: Optional[dict[str, Any]] = None,
) -> dict[str, Any]:
    """Render a Grafana dashboard/panel to an image (managed identity)."""

    args: dict[str, Any] = dict(arguments or {})
    the_uid = dashboardUid if dashboardUid is not None else uid
    if the_uid is not None:
        args.setdefault("dashboardUid", the_uid)
        args.setdefault("uid", the_uid)
    if panelId is not None:
        args.setdefault("panelId", panelId)
    if fromMs is not None:
        args.setdefault("from", fromMs)
        args.setdefault("fromMs", fromMs)
    if toMs is not None:
        args.setdefault("to", toMs)
        args.setdefault("toMs", toMs)
    if width is not None:
        args.setdefault("width", width)
    if height is not None:
        args.setdefault("height", height)

    backend = await asyncio.to_thread(_get_backend)
    return await asyncio.to_thread(backend.tool_call, "amgmcp_image_render", args)


if __name__ == "__main__":
    # Serve a streamable HTTP MCP endpoint + probe routes.
    # Note: we host Starlette ourselves to allow header/payload normalization
    # for connector compatibility while still running the MCP session manager.
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run(app, host=host, port=port, log_level=os.getenv("LOG_LEVEL", "info"))
