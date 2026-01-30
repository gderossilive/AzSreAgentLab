import asyncio
import json
import os
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from typing import Any, Optional

from mcp.server.fastmcp import FastMCP


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


mcp = FastMCP("amg-mcp-http-proxy")

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
    # Bind to the Container App ingress port.
    # Note: FastMCP handles the /mcp endpoint for streamable HTTP.
    mcp.run(transport="streamable-http", host="0.0.0.0", port=8000)
