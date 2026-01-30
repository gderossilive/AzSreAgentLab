import asyncio
import contextlib
import json
import os
import subprocess
import sys
import threading
import time
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

    def _read_message(self, timeout_s: float = 30.0) -> dict[str, Any]:
        # Minimal LSP-style framing: headers until \r\n\r\n then JSON body.
        start = time.time()
        headers = b""
        while b"\r\n\r\n" not in headers:
            if time.time() - start > timeout_s:
                raise TimeoutError("Timed out waiting for MCP headers")
            chunk = self._stdout.read(1)
            if not chunk:
                rc = self._proc.poll()
                raise RuntimeError(f"MCP server stdout closed (returncode={rc})")
            headers += chunk

        header_blob, rest = headers.split(b"\r\n\r\n", 1)
        content_length: Optional[int] = None
        for line in header_blob.split(b"\r\n"):
            if line.lower().startswith(b"content-length:"):
                content_length = int(line.split(b":", 1)[1].strip())
                break
        if content_length is None:
            raise ValueError(f"Missing Content-Length header: {header_blob!r}")

        body = rest
        while len(body) < content_length:
            if time.time() - start > timeout_s:
                raise TimeoutError("Timed out waiting for MCP body")
            chunk = self._stdout.read(content_length - len(body))
            if not chunk:
                rc = self._proc.poll()
                raise RuntimeError(f"MCP server stdout closed while reading body (returncode={rc})")
            body += chunk

        return json.loads(body.decode("utf-8"))

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

        init = self._call("initialize", {"capabilities": {}})
        if init.is_error:
            raise RuntimeError(f"amg-mcp initialize failed: {init.raw.get('error')}")

        tools = self._call("tools/list", {})
        if tools.is_error:
            raise RuntimeError(f"amg-mcp tools/list failed: {tools.raw.get('error')}")

        self._supported_query_keys = _schema_properties(tools.raw, "amgmcp_query_datasource")

    def close(self) -> None:
        self._client.close()

    def _call(self, method: str, params: dict[str, Any], timeout_s: float = 60.0) -> JsonRpcResponse:
        req_id = self._next_id
        self._next_id += 1
        return self._client.request(method, params, req_id=req_id, timeout_s=timeout_s)

    def tool_call(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        if name == "amgmcp_query_datasource" and self._supported_query_keys:
            arguments = {k: v for k, v in arguments.items() if k in self._supported_query_keys}

        resp = self._call("tools/call", {"name": name, "arguments": arguments}, timeout_s=120.0)
        return resp.raw


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

    backend = await asyncio.to_thread(_get_backend)
    return await asyncio.to_thread(backend.tool_call, "amgmcp_datasource_list", {})


@mcp.tool()
async def amgmcp_query_datasource(
    datasourceUid: Optional[str] = None,
    datasourceUID: Optional[str] = None,
    datasource_uid: Optional[str] = None,
    datasourceName: Optional[str] = None,
    query: Optional[str] = None,
    expr: Optional[str] = None,
    limit: Optional[int] = None,
    fromMs: Optional[int] = None,
    toMs: Optional[int] = None,
    startTime: Optional[int] = None,
    endTime: Optional[int] = None,
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
    if datasourceName is not None:
        args["datasourceName"] = datasourceName

    if query is not None:
        args["query"] = query
    if expr is not None:
        args["expr"] = expr

    if limit is not None:
        args["limit"] = limit

    # Time bounds; use whichever keys the backend supports.
    if fromMs is not None:
        args["from"] = fromMs
        args["startTime"] = fromMs
    if toMs is not None:
        args["to"] = toMs
        args["endTime"] = toMs
    if startTime is not None:
        args["startTime"] = startTime
    if endTime is not None:
        args["endTime"] = endTime

    backend = await asyncio.to_thread(_get_backend)
    return await asyncio.to_thread(backend.tool_call, "amgmcp_query_datasource", args)


if __name__ == "__main__":
    # Serve a streamable HTTP MCP endpoint + probe routes.
    # Note: we host Starlette ourselves to allow header/payload normalization
    # for connector compatibility while still running the MCP session manager.
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run(app, host=host, port=port, log_level=os.getenv("LOG_LEVEL", "info"))
