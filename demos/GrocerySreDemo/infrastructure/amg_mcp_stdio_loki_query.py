import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Any


@dataclass
class McpMessage:
    headers: dict[str, str]
    body: dict[str, Any]


def _read_exact(stream, n: int) -> bytes:
    data = b""
    while len(data) < n:
        chunk = stream.read(n - len(data))
        if not chunk:
            raise EOFError("Unexpected EOF")
        data += chunk
    return data


def read_message(stream) -> McpMessage:
    headers: dict[str, str] = {}

    # Read headers (LSP-style): lines ending with \r\n, blank line terminates.
    while True:
        line = stream.readline()
        if not line:
            raise EOFError("EOF while reading headers")
        if line in (b"\n", b"\r\n"):
            break
        decoded = line.decode("utf-8", errors="replace").strip()
        if not decoded:
            break
        if ":" in decoded:
            key, value = decoded.split(":", 1)
            headers[key.strip().lower()] = value.strip()

    if "content-length" not in headers:
        raise ValueError(f"Missing Content-Length header. Headers={headers}")

    length = int(headers["content-length"])
    raw = _read_exact(stream, length)
    body = json.loads(raw.decode("utf-8"))
    return McpMessage(headers=headers, body=body)


def write_message(stream, payload: dict[str, Any]) -> None:
    raw = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    header = f"Content-Length: {len(raw)}\r\n\r\n".encode("ascii")
    stream.write(header)
    stream.write(raw)
    stream.flush()


class McpClient:
    def __init__(self, proc: subprocess.Popen[bytes]):
        self.proc = proc
        self._next_id = 1

    def request(self, method: str, params: dict[str, Any] | None = None, timeout_s: float = 30.0) -> dict[str, Any]:
        req_id = self._next_id
        self._next_id += 1

        payload: dict[str, Any] = {"jsonrpc": "2.0", "id": req_id, "method": method}
        if params is not None:
            payload["params"] = params

        write_message(self.proc.stdin, payload)

        deadline = time.time() + timeout_s
        while time.time() < deadline:
            msg = read_message(self.proc.stdout)
            body = msg.body
            if body.get("id") == req_id:
                return body
            # ignore notifications / other responses
        raise TimeoutError(f"Timed out waiting for response to id={req_id} method={method}")


def choose_first_loki_datasource(ds_resp: dict[str, Any]) -> tuple[str, str]:
    result = ds_resp.get("result") or {}

    # AMG MCP sometimes returns content as text; try to parse JSON inside it.
    content = result.get("content")
    if isinstance(content, list) and content:
        text = content[0].get("text")
        if isinstance(text, str) and text.strip():
            try:
                parsed = json.loads(text)
                if isinstance(parsed, list):
                    for ds in parsed:
                        if str(ds.get("type", "")).lower() == "loki":
                            return str(ds.get("uid")), str(ds.get("name"))
            except Exception:
                pass

    # Or sometimes a structured list in result
    for key in ("datasources", "dataSources"):
        maybe = result.get(key)
        if isinstance(maybe, list):
            for ds in maybe:
                if str(ds.get("type", "")).lower() == "loki":
                    return str(ds.get("uid")), str(ds.get("name"))

    # Last resort: scan any list under result
    if isinstance(result, list):
        for ds in result:
            if str(ds.get("type", "")).lower() == "loki":
                return str(ds.get("uid")), str(ds.get("name"))

    raise RuntimeError(f"No Loki datasource found. Response keys={list(ds_resp.keys())}")


def tool_input_schema(tools_list_resp: dict[str, Any], tool_name: str) -> dict[str, Any] | None:
    result = tools_list_resp.get("result") or {}
    tools = result.get("tools")
    if not isinstance(tools, list):
        return None
    for tool in tools:
        if tool.get("name") == tool_name:
            schema = tool.get("inputSchema")
            if isinstance(schema, dict):
                return schema
    return None


def schema_has(schema: dict[str, Any] | None, prop: str) -> bool:
    if not schema:
        return False
    props = schema.get("properties")
    return isinstance(props, dict) and prop in props


def main() -> int:
    grafana_endpoint = os.environ.get("GRAFANA_ENDPOINT", "").rstrip("/")
    lookback_minutes = int(os.environ.get("LOOKBACK_MINUTES", "15"))
    logql = os.environ.get("LOKI_LOGQL") or '{app="grocery-api"}'
    limit = int(os.environ.get("LIMIT", "20"))

    print(f"[runner] grafana={grafana_endpoint}")
    print(f"[runner] lookbackMinutes={lookback_minutes}")
    print(f"[runner] logql={logql}")

    if not grafana_endpoint:
        print("[runner] ERROR: GRAFANA_ENDPOINT is required", file=sys.stderr)
        return 1

    now_s = int(time.time())
    from_ms = (now_s - lookback_minutes * 60) * 1000
    to_ms = now_s * 1000

    # Start MCP stdio server (amg-mcp)
    cmd = [
        "/usr/local/bin/amg-mcp",
        "--AmgMcpOptions:Transport=Stdio",
        f"--AmgMcpOptions:AzureManagedGrafanaEndpoint={grafana_endpoint}",
    ]

    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )

    assert proc.stdin is not None
    assert proc.stdout is not None

    client = McpClient(proc)

    try:
        init = client.request("initialize", {"capabilities": {}}, timeout_s=30)
        print(f"[runner] initialize_ok={'result' in init}")

        tools = client.request("tools/list", {}, timeout_s=30)
        print(f"[runner] tools_list_ok={'result' in tools}")

        ds = client.request("tools/call", {"name": "amgmcp_datasource_list", "arguments": {}}, timeout_s=60)
        loki_uid, loki_name = choose_first_loki_datasource(ds)
        print(f"[runner] loki_datasource_name={loki_name} uid={loki_uid}")

        schema = tool_input_schema(tools, "amgmcp_query_datasource")
        if schema is None:
            raise RuntimeError("amgmcp_query_datasource not present in tools/list")

        args: dict[str, Any] = {}

        if schema_has(schema, "datasourceUid"):
            args["datasourceUid"] = loki_uid
        if schema_has(schema, "datasourceUID"):
            args["datasourceUID"] = loki_uid
        if schema_has(schema, "datasource_uid"):
            args["datasource_uid"] = loki_uid
        if schema_has(schema, "datasourceName"):
            args["datasourceName"] = loki_name

        if schema_has(schema, "query"):
            args["query"] = logql
        if schema_has(schema, "expr"):
            args["expr"] = logql

        if schema_has(schema, "limit"):
            args["limit"] = limit

        for k, v in (
            ("from", from_ms),
            ("to", to_ms),
            ("startTime", from_ms),
            ("endTime", to_ms),
        ):
            if schema_has(schema, k):
                args[k] = v

        query = client.request(
            "tools/call",
            {"name": "amgmcp_query_datasource", "arguments": args},
            timeout_s=90,
        )

        if "error" in query:
            print(f"[runner] query_error={json.dumps(query['error'])}", file=sys.stderr)
            return 2

        print("[runner] query_ok=true")

        # Print a short preview if present
        content = (query.get("result") or {}).get("content")
        if isinstance(content, list) and content:
            text = content[0].get("text")
            if isinstance(text, str) and text:
                preview = text.replace("\n", " ")[:600]
                print(f"[runner] query_preview={preview}")

        return 0

    except Exception as e:
        print(f"[runner] ERROR: {e}", file=sys.stderr)
        # Dump a bit of MCP server stdout (combined stderr) for clues
        try:
            proc.stdout.flush()
        except Exception:
            pass
        return 1

    finally:
        # Keep alive briefly so logs are retrievable
        time.sleep(30)
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()


if __name__ == "__main__":
    raise SystemExit(main())
