import json
import os
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from typing import Any, Optional


def _env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None or value == "":
        return default
    return int(value)


def _env_str(name: str, default: str) -> str:
    value = os.getenv(name)
    return default if value is None or value == "" else value


def _now_ms() -> int:
    return int(time.time() * 1000)


def _write(msg: str) -> None:
    sys.stdout.write(msg + "\n")
    sys.stdout.flush()


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
        def _header_complete(data: bytes) -> bool:
            return (b"\r\n\r\n" in data) or (b"\n\n" in data)

        while not _header_complete(headers):
            if time.time() - start > timeout_s:
                raise TimeoutError("Timed out waiting for MCP headers")
            chunk = self._stdout.read(1)
            if not chunk:
                rc = self._proc.poll()
                raise RuntimeError(f"MCP server stdout closed (returncode={rc})")
            headers += chunk

        if b"\r\n\r\n" in headers:
            header_blob, rest = headers.split(b"\r\n\r\n", 1)
        else:
            header_blob, rest = headers.split(b"\n\n", 1)
        content_length: Optional[int] = None
        normalized = header_blob.replace(b"\r\n", b"\n")
        for line in normalized.split(b"\n"):
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
        self._send({"jsonrpc": "2.0", "id": req_id, "method": method, "params": params})

        start = time.time()
        while True:
            if time.time() - start > timeout_s:
                raise TimeoutError(f"Timed out waiting for response to {method}")

            msg = self._read_message(timeout_s=timeout_s)

            # Ignore notifications/other IDs.
            if msg.get("id") == req_id:
                return JsonRpcResponse(raw=msg)


def _extract_text_content(resp: dict[str, Any]) -> Optional[str]:
    try:
        content = resp.get("result", {}).get("content")
        if isinstance(content, list) and content:
            first = content[0]
            if isinstance(first, dict) and isinstance(first.get("text"), str):
                return first["text"]
    except Exception:
        return None
    return None


def _maybe_json(text: str) -> Any:
    try:
        return json.loads(text)
    except Exception:
        return None


def _schema_properties(tools_list_resp: dict[str, Any], tool_name: str) -> set[str]:
    tools = tools_list_resp.get("result", {}).get("tools")
    if not isinstance(tools, list):
        return set()
    for tool in tools:
        if isinstance(tool, dict) and tool.get("name") == tool_name:
            schema = tool.get("inputSchema")
            if isinstance(schema, dict):
                props = schema.get("properties")
                if isinstance(props, dict):
                    return set(props.keys())
    return set()


def main() -> int:
    grafana_endpoint = _env_str("GRAFANA_ENDPOINT", "")
    lookback_minutes = _env_int("LOOKBACK_MINUTES", 15)
    logql = _env_str("LOKI_LOGQL", '{app="grocery-api"}')
    limit = _env_int("LIMIT", 20)

    if not grafana_endpoint:
        _write("[runner] ERROR: GRAFANA_ENDPOINT missing")
        return 1

    _write(f"[runner] grafana={grafana_endpoint}")
    _write(f"[runner] lookbackMinutes={lookback_minutes}")
    _write(f"[runner] logql={logql}")

    now = _now_ms()
    start_ms = now - (lookback_minutes * 60 * 1000)

    # Start the MCP server locally (in-container) in stdio mode.
    argv = [
        "/usr/local/bin/amg-mcp",
        "--AmgMcpOptions:Transport=Stdio",
        f"--AmgMcpOptions:AzureManagedGrafanaEndpoint={grafana_endpoint}",
    ]

    client = McpStdioClient(argv)
    try:
        init = client.request("initialize", {"capabilities": {}}, req_id=1)
        _write(f"[runner] initialize_ok={not init.is_error}")
        if init.is_error:
            _write(f"[runner] initialize_error={json.dumps(init.raw.get('error'))}")
            return 1

        tools = client.request("tools/list", {}, req_id=2)
        _write(f"[runner] tools_list_ok={not tools.is_error}")
        if tools.is_error:
            _write(f"[runner] tools_list_error={json.dumps(tools.raw.get('error'))}")
            return 1

        # Datasource list
        ds = client.request(
            "tools/call",
            {"name": "amgmcp_datasource_list", "arguments": {}},
            req_id=3,
        )
        if ds.is_error:
            _write(f"[runner] datasource_list_error={json.dumps(ds.raw.get('error'))}")
            return 1

        ds_text = _extract_text_content(ds.raw)
        ds_list: Any
        if ds_text:
            parsed = _maybe_json(ds_text)
            ds_list = parsed if parsed is not None else ds_text
        else:
            ds_list = ds.raw.get("result")

        loki_uid = None
        loki_name = None
        if isinstance(ds_list, list):
            for item in ds_list:
                if not isinstance(item, dict):
                    continue
                if str(item.get("type", "")).lower() == "loki":
                    loki_uid = item.get("uid")
                    loki_name = item.get("name")
                    break

        if not loki_uid:
            _write("[runner] ERROR: no Loki datasource found")
            preview = json.dumps(ds_list)[:800] if not isinstance(ds_list, str) else ds_list[:800]
            _write(f"[runner] datasource_list_preview={preview}")
            return 1

        _write(f"[runner] loki_datasource_name={loki_name} uid={loki_uid}")

        supported_keys = _schema_properties(tools.raw, "amgmcp_query_datasource")
        if not supported_keys:
            _write("[runner] WARN: could not determine amgmcp_query_datasource schema; sending minimal args")

        args: dict[str, Any] = {}
        def put(key: str, value: Any) -> None:
            if not supported_keys or key in supported_keys:
                args[key] = value

        put("datasourceUid", loki_uid)
        put("datasourceUID", loki_uid)
        put("datasource_uid", loki_uid)
        put("datasourceName", loki_name)
        put("query", logql)
        put("expr", logql)
        put("limit", limit)
        put("from", start_ms)
        put("to", now)
        put("startTime", start_ms)
        put("endTime", now)

        q = client.request(
            "tools/call",
            {"name": "amgmcp_query_datasource", "arguments": args},
            req_id=4,
            timeout_s=120.0,
        )

        if q.is_error:
            _write(f"[runner] query_error={json.dumps(q.raw.get('error'))}")
            return 1

        _write("[runner] query_ok=true")
        preview_text = _extract_text_content(q.raw)
        if preview_text:
            _write(f"[runner] query_preview={preview_text[:800].replace(chr(10), ' ')}")
        else:
            _write(f"[runner] query_result_preview={json.dumps(q.raw.get('result'))[:800]}")

        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
