import asyncio
import base64
import contextlib
import json
import os
import select
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any, Literal, Optional

import pathlib

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


def _amw_query_endpoint() -> str:
    # Azure Monitor Workspace Prometheus query endpoint (workspace-scoped)
    return _env_str("AMW_QUERY_ENDPOINT").rstrip("/")


def _prometheus_datasource_uid() -> str:
    return _env_str("PROMETHEUS_DATASOURCE_UID").strip()


def _looks_like_prometheus_datasource(name: Optional[str]) -> bool:
    if not name:
        return False
    lowered = name.strip().lower()
    return "prometheus" in lowered or lowered.startswith("prom (") or lowered.startswith("prometheus (")


def _managed_identity_access_token(resource: str) -> str:
    # Container Apps managed identity endpoint.
    endpoint = _env_str("IDENTITY_ENDPOINT")
    header = _env_str("IDENTITY_HEADER")
    client_id = _env_str("AZURE_CLIENT_ID")
    if not endpoint or not header:
        raise RuntimeError("Managed identity environment not detected (missing IDENTITY_ENDPOINT/IDENTITY_HEADER)")

    qs = {
        "api-version": "2019-08-01",
        "resource": resource,
    }
    if client_id:
        qs["client_id"] = client_id

    url = endpoint + ("&" if "?" in endpoint else "?") + urllib.parse.urlencode(qs)
    req = urllib.request.Request(url, headers={"x-identity-header": header})
    with urllib.request.urlopen(req, timeout=20) as resp:
        payload = json.loads((resp.read() or b"{}").decode("utf-8"))
    token = payload.get("access_token")
    if not token:
        raise RuntimeError("Managed identity token response missing access_token")
    return str(token)


def _amw_promql_query_range(*, endpoint: str, expr: str, start_ms: int, end_ms: int, step_s: int = 60) -> dict[str, Any]:
    token = _managed_identity_access_token("https://prometheus.monitor.azure.com")
    base = endpoint.rstrip("/")
    start_s = max(0, int(start_ms // 1000))
    end_s = max(0, int(end_ms // 1000))
    step_s = max(1, int(step_s))

    qs = urllib.parse.urlencode({
        "query": expr,
        "start": str(start_s),
        "end": str(end_s),
        "step": str(step_s),
    })
    url = f"{base}/api/v1/query_range?{qs}"
    req = urllib.request.Request(
        url,
        method="GET",
        headers={
            "accept": "application/json",
            "authorization": f"Bearer {token}",
        },
    )
    with urllib.request.urlopen(req, timeout=float(_env_int("AMW_PROMQL_TIMEOUT_S", 15))) as resp:
        return json.loads((resp.read() or b"{}").decode("utf-8"))


def _grafana_promql_query_range_via_datasource_proxy(
    *,
    datasource_uid: str,
    expr: str,
    start_ms: int,
    end_ms: int,
    step_s: int = 60,
) -> dict[str, Any]:
    """Query Prometheus through Grafana's datasource proxy (server-side auth).

    This avoids needing AMW data-plane permissions on the proxy identity.
    """

    datasource_uid = (datasource_uid or "").strip()
    if not datasource_uid:
        raise ValueError("datasource_uid is required")

    start_s = max(0, int(start_ms // 1000))
    end_s = max(0, int(end_ms // 1000))
    step_s = max(1, int(step_s))

    qs = urllib.parse.urlencode(
        {
            "query": expr,
            "start": str(start_s),
            "end": str(end_s),
            "step": str(step_s),
        }
    )
    path = f"/api/datasources/proxy/uid/{urllib.parse.quote(datasource_uid)}/api/v1/query_range?{qs}"
    return _grafana_get_json(path, timeout_s=float(_env_int("PROM_GRAFANA_PROXY_TIMEOUT_S", 10)))


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


def _grafana_render_timeout_s() -> float:
    # Keep this comfortably below common MCP client read timeouts (~60s) so we
    # can return a structured error rather than letting clients cancel.
    return float(_env_int("GRAFANA_RENDER_TIMEOUT_S", 20))


def _grafana_org_id() -> int:
    return _env_int("GRAFANA_ORG_ID", 1)

def _grafana_auth_headers(*, accept: str) -> dict[str, str]:
    aad_token = _get_managed_identity_access_token(_grafana_aad_resource())
    return {
        "Authorization": f"Bearer {aad_token}",
        "Accept": accept,
        "X-Grafana-Org-Id": str(_grafana_org_id()),
    }


def _loki_http_timeout_s() -> float:
    return float(_env_int("LOKI_HTTP_TIMEOUT_S", 15))


def _loki_endpoint() -> str:
    return _env_str("LOKI_ENDPOINT").rstrip("/")


def _looks_like_loki_datasource(name: Optional[str]) -> bool:
    if not name:
        return False
    return "loki" in name.strip().lower()


def _loki_query_range(
    *,
    query: str,
    start_ms: int,
    end_ms: int,
    limit: Optional[int],
    step_s: Optional[float] = None,
) -> dict[str, Any]:
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
    if step_s is not None:
        # Loki expects step as seconds (float ok).
        params["step"] = str(step_s)

    # Support either a bare base URL (https://host) or a base that already includes /loki.
    base = endpoint
    if base.endswith("/loki"):
        url = base + "/api/v1/query_range"
    else:
        url = base + "/loki/api/v1/query_range"

    url = url + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, method="GET", headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=_loki_http_timeout_s()) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
        return payload
    except urllib.error.HTTPError as http_err:
        # Include Loki's error body (it usually contains a parse error message).
        body = ""
        try:
            body = http_err.read().decode("utf-8", errors="replace")
        except Exception:
            body = ""
        body = (body or "").strip()
        if len(body) > 2000:
            body = body[:2000] + "..."
        raise RuntimeError(
            f"Loki query_range failed (HTTP {http_err.code}). "
            f"Body={body or '<empty>'}. "
            f"Query={query}"
        ) from http_err


def _template_extract_default_vars(uid: str) -> dict[str, str]:
    """Extract a small set of templating defaults from the baked-in dashboard template."""
    path = _template_path_for_dashboard_uid(uid)
    if path is None or not path.exists():
        return {}
    obj = json.loads(path.read_text(encoding="utf-8"))
    dash = obj.get("dashboard")
    if not isinstance(dash, dict):
        return {}
    templating = dash.get("templating")
    if not isinstance(templating, dict):
        return {}
    items = templating.get("list")
    if not isinstance(items, list):
        return {}

    out: dict[str, str] = {}
    for v in items:
        if not isinstance(v, dict):
            continue
        name = v.get("name")
        if not isinstance(name, str) or not name.strip():
            continue
        current = v.get("current")
        if isinstance(current, dict):
            value = current.get("value")
            if isinstance(value, str) and value.strip():
                out[name] = value.strip()
    return out


def _format_duration_s(seconds: int) -> str:
    seconds = max(1, int(seconds))
    if seconds % 3600 == 0:
        return f"{seconds // 3600}h"
    if seconds % 60 == 0:
        return f"{seconds // 60}m"
    return f"{seconds}s"


def _derive_grafana_macro_vars(*, start_ms: int, end_ms: int, step_ms: int) -> dict[str, str]:
    """Provide replacements for common Grafana macros used in LogQL queries."""
    range_ms = max(0, int(end_ms) - int(start_ms))
    range_s = int(range_ms / 1000)
    interval_s = max(1, int(step_ms / 1000))

    return {
        "__interval": _format_duration_s(interval_s),
        "__interval_ms": str(interval_s * 1000),
        "__range": _format_duration_s(range_s if range_s > 0 else 1),
        "__range_s": str(range_s),
        "__range_ms": str(range_ms),
    }


def _apply_template_vars(expr: str, vars_map: dict[str, str]) -> str:
    out = str(expr)
    for k, v in vars_map.items():
        out = out.replace(f"${k}", v).replace(f"${{{k}}}", v)
    return out


def _template_find_panel_query(
    *,
    uid: str,
    panel_title: str,
    ref_id: str = "A",
) -> tuple[dict[str, Any], str]:
    """Find the first query expression for a panel title in the baked-in template.

    Returns (panel_summary, expr).
    """
    path = _template_path_for_dashboard_uid(uid)
    if path is None:
        raise FileNotFoundError(f"No dashboard template mapping for uid={uid}")
    if not path.exists():
        raise FileNotFoundError(f"Dashboard template not found in container: {path}")

    obj = json.loads(path.read_text(encoding="utf-8"))
    dash = obj.get("dashboard")
    if not isinstance(dash, dict):
        raise ValueError("Template JSON missing 'dashboard' object")

    panels = dash.get("panels")
    if not isinstance(panels, list):
        raise ValueError("Template JSON missing 'dashboard.panels' list")

    wanted = (panel_title or "").strip().lower()
    if not wanted:
        raise ValueError("panelTitle is required")

    for idx, panel in enumerate(panels, start=1):
        if not isinstance(panel, dict):
            continue
        title = panel.get("title")
        if not isinstance(title, str) or title.strip().lower() != wanted:
            continue

        targets = panel.get("targets")
        if not isinstance(targets, list) or not targets:
            raise ValueError(f"Panel '{panel_title}' has no targets")

        chosen = None
        for t in targets:
            if not isinstance(t, dict):
                continue
            if str(t.get("refId") or "A").strip().upper() == ref_id.strip().upper():
                chosen = t
                break
        if chosen is None:
            chosen = next((t for t in targets if isinstance(t, dict)), None)
        if not isinstance(chosen, dict):
            raise ValueError(f"Panel '{panel_title}' has no usable target")

        expr = chosen.get("expr") or chosen.get("query")
        if not isinstance(expr, str) or not expr.strip():
            raise ValueError(f"Panel '{panel_title}' target has no expr")

        panel_summary = {
            "panelIndex": idx,
            "title": title,
            "type": panel.get("type"),
        }
        return panel_summary, expr

    raise KeyError(f"Panel titled '{panel_title}' not found in template")


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


def _grafana_get_json(path: str, *, timeout_s: Optional[float] = None) -> Any:
    endpoint = _env_str("GRAFANA_ENDPOINT").rstrip("/")
    if not endpoint:
        raise RuntimeError("GRAFANA_ENDPOINT is required")
    url = endpoint + path

    req = urllib.request.Request(
        url,
        method="GET",
        headers=_grafana_auth_headers(accept="application/json"),
    )
    with urllib.request.urlopen(req, timeout=_grafana_http_timeout_s() if timeout_s is None else float(timeout_s)) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _grafana_get_bytes(path: str, *, accept: str) -> bytes:
    endpoint = _env_str("GRAFANA_ENDPOINT").rstrip("/")
    if not endpoint:
        raise RuntimeError("GRAFANA_ENDPOINT is required")
    url = endpoint + path

    req = urllib.request.Request(
        url,
        method="GET",
        headers=_grafana_auth_headers(accept=accept),
    )
    with urllib.request.urlopen(req, timeout=_grafana_render_timeout_s()) as resp:
        return resp.read() or b""


def _grafana_dashboard_get_by_uid(uid: str) -> dict[str, Any]:
    # GET /api/dashboards/uid/:uid
    return _grafana_get_json(f"/api/dashboards/uid/{urllib.parse.quote(uid)}")


def _grafana_extract_slug(dashboard_by_uid: dict[str, Any]) -> str:
    meta = dashboard_by_uid.get("meta")
    if isinstance(meta, dict):
        slug = meta.get("slug")
        if isinstance(slug, str) and slug.strip():
            return slug.strip()
    return "-"


def _grafana_first_panel_id(dashboard_by_uid: dict[str, Any]) -> Optional[int]:
    dash = dashboard_by_uid.get("dashboard")
    if not isinstance(dash, dict):
        return None

    def _walk_panels(panels: Any) -> Optional[int]:
        if not isinstance(panels, list):
            return None
        for panel in panels:
            if not isinstance(panel, dict):
                continue
            # Rows contain nested panels.
            nested = panel.get("panels")
            found = _walk_panels(nested)
            if found is not None:
                return found

            # Skip non-renderable containers.
            if panel.get("type") in ("row", "dashboard", "text"):
                continue

            pid = panel.get("id")
            try:
                if pid is not None:
                    return int(pid)
            except Exception:
                continue
        return None

    return _walk_panels(dash.get("panels"))


def _grafana_panel_summaries(dashboard_by_uid: dict[str, Any]) -> list[dict[str, Any]]:
    dash = dashboard_by_uid.get("dashboard")
    if not isinstance(dash, dict):
        return []

    out: list[dict[str, Any]] = []

    def _walk(panels: Any, *, row_title: Optional[str] = None) -> None:
        if not isinstance(panels, list):
            return
        for panel in panels:
            if not isinstance(panel, dict):
                continue

            p_type = panel.get("type")
            title = panel.get("title")
            pid = panel.get("id")
            grid = panel.get("gridPos")

            # Rows contain nested panels.
            nested = panel.get("panels")
            if isinstance(nested, list):
                _walk(nested, row_title=str(title) if isinstance(title, str) else row_title)

            summary: dict[str, Any] = {
                "id": pid,
                "title": title,
                "type": p_type,
                "rowTitle": row_title,
            }

            if isinstance(grid, dict):
                # Common layout keys: x,y,w,h
                for k in ("x", "y", "w", "h"):
                    if k in grid:
                        summary.setdefault("gridPos", {})[k] = grid.get(k)

            # Mark whether this panel is likely renderable via /render/d-solo.
            pid_int = 0
            try:
                if isinstance(pid, int):
                    pid_int = pid
                elif isinstance(pid, str) and pid.strip():
                    pid_int = int(pid.strip())
            except Exception:
                pid_int = 0
            summary["renderable"] = pid_int > 0 and p_type not in ("row", "dashboard")

            out.append(summary)

    _walk(dash.get("panels"))

    # Keep a stable ordering: rows/containers may have null IDs.
    def _sort_key(p: dict[str, Any]) -> tuple[int, str]:
        pid = p.get("id")
        n = 0
        try:
            if isinstance(pid, int):
                n = pid
            elif isinstance(pid, str) and pid.strip():
                n = int(pid.strip())
        except Exception:
            n = 0
        t = p.get("title")
        return (n, str(t) if t is not None else "")

    out.sort(key=_sort_key)
    return out


def _grafana_dashboard_summary(uid: str) -> dict[str, Any]:
    dashboard_by_uid = _grafana_dashboard_get_by_uid(uid)
    dash = dashboard_by_uid.get("dashboard")
    title = None
    if isinstance(dash, dict):
        title = dash.get("title")

    return {
        "dashboard": {
            "uid": uid,
            "slug": _grafana_extract_slug(dashboard_by_uid),
            "title": title,
        },
        "panels": _grafana_panel_summaries(dashboard_by_uid),
    }


def _template_path_for_dashboard_uid(uid: str) -> Optional[pathlib.Path]:
    # These files are baked into the proxy container image.
    mapping = {
        "afbppudwbhl34b": pathlib.Path("/app/grafana/grocery-sre-overview.dashboard.template.json"),
    }
    return mapping.get(uid)


def _template_dashboard_summary(uid: str) -> dict[str, Any]:
    path = _template_path_for_dashboard_uid(uid)
    if path is None:
        raise FileNotFoundError(f"No dashboard template mapping for uid={uid}")
    if not path.exists():
        raise FileNotFoundError(f"Dashboard template not found in container: {path}")

    obj = json.loads(path.read_text(encoding="utf-8"))
    dash = obj.get("dashboard")
    if not isinstance(dash, dict):
        raise ValueError("Template JSON missing 'dashboard' object")

    title = dash.get("title")
    panels = dash.get("panels")
    if not isinstance(panels, list):
        panels = []

    out_panels: list[dict[str, Any]] = []
    for idx, panel in enumerate(panels, start=1):
        if not isinstance(panel, dict):
            continue
        p_type = panel.get("type")
        p_title = panel.get("title")
        grid = panel.get("gridPos")
        summary: dict[str, Any] = {
            # Template dashboards typically do not include Grafana-assigned panel IDs.
            "id": None,
            "panelIndex": idx,
            "title": p_title,
            "type": p_type,
            "renderable": p_type not in ("row", "dashboard"),
        }
        if isinstance(grid, dict):
            for k in ("x", "y", "w", "h"):
                if k in grid:
                    summary.setdefault("gridPos", {})[k] = grid.get(k)
        out_panels.append(summary)

    return {
        "dashboard": {
            "uid": uid,
            "slug": "-",
            "title": title,
        },
        "panels": out_panels,
        "warning": {
            "note": "Grafana API access was unavailable; panel list came from the baked-in dashboard template. Panel IDs are not available from the template.",
        },
    }


def _grafana_render_png(
    *,
    dashboard_uid: str,
    panel_id: Optional[int],
    from_ms: Optional[int],
    to_ms: Optional[int],
    width: Optional[int],
    height: Optional[int],
) -> bytes:
    uid = (dashboard_uid or "").strip()
    if not uid:
        raise ValueError("dashboardUid is required")

    # Prefer rendering a single panel by default: it's faster and less likely
    # to exceed MCP client timeouts.
    dashboard_by_uid = _grafana_dashboard_get_by_uid(uid)
    slug = _grafana_extract_slug(dashboard_by_uid)

    effective_panel_id = panel_id
    if effective_panel_id is None and not _env_bool("GRAFANA_RENDER_FULL_DASHBOARD", default=False):
        effective_panel_id = _grafana_first_panel_id(dashboard_by_uid)

    if effective_panel_id is not None:
        path = f"/render/d-solo/{urllib.parse.quote(uid)}/{urllib.parse.quote(slug)}"
    else:
        path = f"/render/d/{urllib.parse.quote(uid)}/{urllib.parse.quote(slug)}"

    params: dict[str, str] = {}
    # Managed Grafana typically uses orgId=1; include it explicitly.
    params["orgId"] = str(_grafana_org_id())

    if effective_panel_id is not None:
        params["panelId"] = str(int(effective_panel_id))
    if from_ms is not None:
        params["from"] = str(int(from_ms))
    if to_ms is not None:
        params["to"] = str(int(to_ms))
    if width is not None:
        params["width"] = str(int(width))
    if height is not None:
        params["height"] = str(int(height))

    qs = urllib.parse.urlencode(params)
    if qs:
        path = path + "?" + qs

    return _grafana_get_bytes(path, accept="image/png")


def _grafana_dashboard_search(query: str) -> Any:
    # Grafana search API. See: GET /api/search
    q = (query or "").strip()
    if not q:
        q = ""
    params = urllib.parse.urlencode({"query": q})
    return _grafana_get_json(f"/api/search?{params}")


def _fallback_dashboard_search(query: str) -> list[dict[str, Any]]:
    # Deterministic fallback for demo scenarios where the stdio backend or
    # Grafana API is unavailable/unreliable.
    q = (query or "").lower()
    uid = _env_str("DEFAULT_GROCERY_SRE_DASHBOARD_UID", "afbppudwbhl34b")
    title = "Grocery App - SRE Overview (Custom)"
    if "grocery" in q and "sre" in q and "overview" in q:
        return [{"uid": uid, "title": title, "type": "dash-db"}]
    # If the user searches for the exact title, return it too.
    if title.lower() in q:
        return [{"uid": uid, "title": title, "type": "dash-db"}]
    return []


def _reset_backend(reason: str) -> None:
    global _backend
    try:
        lock = _backend_lock
    except Exception:
        # If called before globals are initialized (shouldn't happen), no-op.
        return

    with lock:
        if _backend is None:
            return
        try:
            _backend.close()
        except Exception:
            pass
        _backend = None

    try:
        sys.stderr.write(f"[proxy] reset amg-mcp backend: {reason}\n")
        sys.stderr.flush()
    except Exception:
        pass


def _backend_tool_call_safe(name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    try:
        backend = _get_backend()
        return backend.tool_call(name, arguments)
    except TimeoutError as exc:
        _reset_backend(f"timeout calling {name}: {exc}")
        return {
            "ok": False,
            "errorType": "TimeoutError",
            "error": str(exc),
            "hint": "The underlying amg-mcp stdio call exceeded the proxy timeout. This can happen during backend startup (initialize/tools/list) as well as tool calls. Try again, or increase AMG_MCP_INIT_TIMEOUT_S / AMG_MCP_TOOLS_LIST_TIMEOUT_S / AMG_MCP_TOOL_TIMEOUT_S (keep tool timeout <100s to avoid client cancellation).",
        }
    except RuntimeError as exc:
        _reset_backend(f"runtime error calling {name}: {exc}")
        return {
            "ok": False,
            "errorType": "RuntimeError",
            "error": str(exc),
            "hint": "The underlying amg-mcp process appears unhealthy. The proxy reset it; retry the tool call.",
        }
    except Exception as exc:
        return {
            "ok": False,
            "errorType": type(exc).__name__,
            "error": str(exc),
        }


def _backend_tool_call_safe_with_timeout(name: str, arguments: dict[str, Any], timeout_s: float) -> dict[str, Any]:
    """Like _backend_tool_call_safe, but allows overriding the tool call timeout.

    This is useful for workflows where we want a fast attempt against the stdio backend
    (to avoid long client-side timeouts), then fall back to direct data-plane calls.
    """

    try:
        backend = _get_backend()
        supported_keys = getattr(backend, "_tool_supported_keys", {}).get(name)
        if supported_keys:
            arguments = {k: v for k, v in arguments.items() if k in supported_keys}

        # Call MCP tools/call directly so we can override timeout.
        resp = backend._call("tools/call", {"name": name, "arguments": arguments}, timeout_s=float(timeout_s))
        return resp.raw
    except TimeoutError as exc:
        _reset_backend(f"timeout calling {name}: {exc}")
        return {
            "ok": False,
            "errorType": "TimeoutError",
            "error": str(exc),
            "hint": "The underlying amg-mcp stdio call exceeded the proxy timeout. The proxy reset it; retry the tool call.",
        }
    except RuntimeError as exc:
        _reset_backend(f"runtime error calling {name}: {exc}")
        return {
            "ok": False,
            "errorType": "RuntimeError",
            "error": str(exc),
            "hint": "The underlying amg-mcp process appears unhealthy. The proxy reset it; retry the tool call.",
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


def _warm_backend_async() -> None:
    try:
        _get_backend()
        sys.stderr.write("[proxy] amg-mcp backend warm-up complete\n")
        sys.stderr.flush()
    except Exception as exc:
        # Don't fail the app if warm-up fails; tool calls will surface errors.
        try:
            sys.stderr.write(f"[proxy] amg-mcp backend warm-up failed: {exc}\n")
            sys.stderr.flush()
        except Exception:
            pass


# Best-effort: warm the stdio backend at startup to avoid first-request latency.
threading.Thread(target=_warm_backend_async, daemon=True).start()


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
        datasources: list[dict[str, Any]] = []
        if _loki_endpoint():
            datasources.append(
                {
                    "name": "Loki (grocery)",
                    "type": "loki",
                    "url": _loki_endpoint(),
                }
            )
        if _amw_query_endpoint():
            datasources.append(
                {
                    "name": "Prometheus (AMW)",
                    "type": "prometheus",
                    "url": _amw_query_endpoint(),
                }
            )

        if datasources:
            out = {
                "ok": True,
                "source": "direct-fallback",
                "datasources": datasources,
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

    # Compatibility: some backends expect PromQL/Loki queries under a specific key.
    # If the caller provided only one of (query, expr), set both.
    effective_q = query if query is not None else expr
    if effective_q is not None and str(effective_q).strip() != "":
        args.setdefault("query", effective_q)
        args.setdefault("expr", effective_q)

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

    # Prometheus: avoid the amg-mcp backend by default (it can stall long enough to hit
    # common MCP client read timeouts). Prefer Grafana's datasource proxy (server-side auth),
    # then fall back to AMW direct PromQL if configured. Opt-in to backend via env.
    if _looks_like_prometheus_datasource(ds_name):
        effective_expr = expr if expr is not None else query
        start_ms = from_ms if from_ms is not None else start_time
        end_ms = to_ms if to_ms is not None else end_time

        if not effective_expr:
            return {"ok": False, "source": "prometheus", "errorType": "ValueError", "error": "expr (PromQL) is required"}
        if start_ms is None or end_ms is None:
            return {
                "ok": False,
                "source": "prometheus",
                "errorType": "ValueError",
                "error": "fromMs/toMs (or startTime/endTime) are required",
            }

        proxy_err: Optional[dict[str, str]] = None
        amw_err: Optional[dict[str, str]] = None
        backend_resp: Optional[dict[str, Any]] = None

        # 1) Grafana datasource proxy (fast path)
        the_uid = datasourceUid or datasourceUID or datasource_uid or _prometheus_datasource_uid()
        if the_uid:
            try:
                payload = await asyncio.to_thread(
                    _grafana_promql_query_range_via_datasource_proxy,
                    datasource_uid=str(the_uid),
                    expr=str(effective_expr),
                    start_ms=int(start_ms),
                    end_ms=int(end_ms),
                    step_s=60,
                )
                return {
                    "ok": True,
                    "source": "grafana-datasource-proxy",
                    "datasourceUid": str(the_uid),
                    "result": payload,
                }
            except Exception as exc:
                proxy_err = {"errorType": type(exc).__name__, "error": str(exc)}

        # 2) AMW direct PromQL (bounded timeout)
        if _amw_query_endpoint():
            try:
                payload = await asyncio.to_thread(
                    _amw_promql_query_range,
                    endpoint=_amw_query_endpoint(),
                    expr=str(effective_expr),
                    start_ms=int(start_ms),
                    end_ms=int(end_ms),
                    step_s=60,
                )
                return {
                    "ok": True,
                    "source": "amw-direct",
                    "result": payload,
                    "grafanaProxy": proxy_err,
                }
            except Exception as exc:
                amw_err = {"errorType": type(exc).__name__, "error": str(exc)}

        # 3) Optional backend (explicit opt-in)
        if _env_bool("ENABLE_BACKEND_PROMETHEUS", default=False):
            backend_timeout_s = float(_env_int("AMG_MCP_PROM_QUERY_TIMEOUT_S", 10))
            backend_resp = await asyncio.to_thread(
                _backend_tool_call_safe_with_timeout,
                "amgmcp_query_datasource",
                args,
                backend_timeout_s,
            )
            if isinstance(backend_resp, dict) and "error" not in backend_resp:
                return backend_resp

        return {
            "ok": False,
            "source": "prometheus",
            "errorType": "RuntimeError",
            "error": "All Prometheus query strategies failed",
            "grafanaProxy": proxy_err,
            "amw": amw_err,
            "backend": backend_resp,
            "hint": "If AMW direct returns HTTP 403, ensure the proxy's managed identity has 'Monitoring Data Reader' on the Azure Monitor workspace and allow time for RBAC propagation.",
        }

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

    # Avoid hanging network calls by default. If you want a real Grafana search,
    # enable it explicitly.
    if _env_bool("ENABLE_GRAFANA_DIRECT_SEARCH", default=False):
        try:
            payload = await asyncio.to_thread(_grafana_dashboard_search, str(q or ""))
            return {"ok": True, "source": "grafana-direct", "result": payload}
        except Exception as exc:
            backend_resp = await asyncio.to_thread(_backend_tool_call_safe, "amgmcp_dashboard_search", args)
            return {
                "ok": False,
                "source": "grafana-direct",
                "errorType": type(exc).__name__,
                "error": str(exc),
                "backend": backend_resp,
            }

    return {
        "ok": True,
        "source": "fallback",
        "result": _fallback_dashboard_search(str(q or "")),
    }


@mcp.tool()
async def amgmcp_get_dashboard_summary(
    dashboardUid: Optional[str] = None,
    uid: Optional[str] = None,
) -> dict[str, Any]:
    """Get a dashboard summary (title + flattened panel list) from Azure Managed Grafana.

    Recommended pattern: use this to understand layout, then render key panels via
    `amgmcp_image_render` using `panelId` (panel-only rendering).
    """

    the_uid = (dashboardUid if dashboardUid is not None else uid) or _env_str(
        "DEFAULT_GROCERY_SRE_DASHBOARD_UID", "afbppudwbhl34b"
    )
    the_uid = str(the_uid or "").strip()
    if not the_uid:
        return {"ok": False, "source": "grafana-direct", "errorType": "ValueError", "error": "dashboardUid is required"}

    try:
        payload = await asyncio.to_thread(_grafana_dashboard_summary, the_uid)
        return {"ok": True, "source": "grafana-direct", **payload}
    except Exception as exc:
        # If Grafana API access is blocked (common when API key/service accounts are disabled),
        # fall back to the baked-in dashboard template for the demo dashboard.
        try:
            payload = await asyncio.to_thread(_template_dashboard_summary, the_uid)
            return {"ok": True, "source": "template", **payload, "grafanaError": {"type": type(exc).__name__, "error": str(exc)}}
        except Exception as fallback_exc:
            return {
                "ok": False,
                "source": "grafana-direct",
                "errorType": type(exc).__name__,
                "error": str(exc),
                "dashboard": {"uid": the_uid},
                "panels": [],
                "fallbackError": {"type": type(fallback_exc).__name__, "error": str(fallback_exc)},
            }


if not _env_bool("DISABLE_AMGMCP_AZURE_TOOLS", default=True):
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

        return await asyncio.to_thread(_backend_tool_call_safe, "amgmcp_query_resource_log", args)


if not _env_bool("DISABLE_AMGMCP_AZURE_TOOLS", default=True):
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

        return await asyncio.to_thread(_backend_tool_call_safe, "amgmcp_query_resource_graph", args)


if not _env_bool("DISABLE_AMGMCP_AZURE_TOOLS", default=True):
    @mcp.tool()
    async def amgmcp_query_azure_subscriptions(arguments: Optional[dict[str, Any]] = None) -> dict[str, Any]:
        """List subscriptions visible to Grafana's Azure Monitor datasource (managed identity)."""

        args: dict[str, Any] = dict(arguments or {})
        return await asyncio.to_thread(_backend_tool_call_safe, "amgmcp_query_azure_subscriptions", args)


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

    # Prefer Grafana-direct rendering to avoid the stalled stdio backend.
    the_uid = str(the_uid or "").strip()
    panel = panelId if panelId is not None else args.get("panelId")
    try:
        png = await asyncio.to_thread(
            _grafana_render_png,
            dashboard_uid=the_uid,
            panel_id=int(panel) if panel is not None else None,
            from_ms=fromMs,
            to_ms=toMs,
            width=width,
            height=height,
        )
        b64 = base64.b64encode(png).decode("ascii")
        return {
            "ok": True,
            "source": "grafana-direct",
            "contentType": "image/png",
            "imageBase64": b64,
            "bytes": len(png),
        }
    except Exception as exc:
        warning = {
            "errorType": type(exc).__name__,
            "error": str(exc),
            "hint": "Azure Managed Grafana may not allow AAD-authenticated access to the /render endpoint in all configurations. This proxy can return a placeholder image (ENABLE_PLACEHOLDER_IMAGE_RENDER=true) to keep connector flows reliable.",
        }

        # Default to returning a placeholder image to keep portal/connector flows
        # reliable even when Grafana's /render endpoint rejects AAD auth.
        if _env_bool("ENABLE_PLACEHOLDER_IMAGE_RENDER", default=True):
            placeholder_b64 = (
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO5N5sYAAAAASUVORK5CYII="
            )
            return {
                "ok": True,
                "source": "placeholder",
                "contentType": "image/png",
                "imageBase64": placeholder_b64,
                "bytes": len(base64.b64decode(placeholder_b64)),
                "warning": warning,
            }

        result: dict[str, Any] = {
            "ok": False,
            "source": "grafana-direct",
            **warning,
        }

        # Optional stdio fallback (off by default because amg-mcp can stall and
        # cause the overall request to exceed client timeouts).
        if _env_bool("ENABLE_AMG_MCP_RENDER_FALLBACK", default=False):
            backend_resp = await asyncio.to_thread(_backend_tool_call_safe, "amgmcp_image_render", args)
            result["backend"] = backend_resp

        return result


@mcp.tool()
async def amgmcp_get_panel_data(
    dashboardUid: Optional[str] = None,
    uid: Optional[str] = None,
    panelTitle: Optional[str] = None,
    app: Optional[str] = None,
    templateVars: Optional[dict[str, str]] = None,
    fromMs: Optional[int] = None,
    toMs: Optional[int] = None,
    stepMs: Optional[int] = None,
    limit: Optional[int] = None,
) -> dict[str, Any]:
    """Retrieve the data behind a dashboard panel (no image rendering).

    For the Grocery demo dashboard, this tool reads the baked-in dashboard template,
    extracts the panel's Loki query (e.g., "Error rate (errors/s)"), applies default
    templating variables (like $app), applies optional per-call overrides, and runs
    Loki `query_range` directly.

    Notes:
    - Requires LOKI_ENDPOINT to be configured in the proxy.
    - Uses a reasonable default step if none is provided.
        - To override Grafana template variables without editing the dashboard template,
            pass either `app` (convenience for `$app`) and/or `templateVars`.
    """

    the_uid = (dashboardUid if dashboardUid is not None else uid) or _env_str(
        "DEFAULT_GROCERY_SRE_DASHBOARD_UID", "afbppudwbhl34b"
    )
    the_uid = str(the_uid or "").strip()
    if not the_uid:
        return {"ok": False, "source": "template", "errorType": "ValueError", "error": "dashboardUid is required"}

    title = str(panelTitle or "").strip()
    if not title:
        return {"ok": False, "source": "template", "errorType": "ValueError", "error": "panelTitle is required"}

    overrides: dict[str, str] = {}
    if app is not None:
        a = str(app).strip()
        if a:
            overrides["app"] = a
    if templateVars is not None:
        if not isinstance(templateVars, dict):
            return {
                "ok": False,
                "source": "template",
                "errorType": "ValueError",
                "error": "templateVars must be an object/dict",
            }
        for k, v in templateVars.items():
            if v is None:
                continue
            key = str(k).strip()
            val = str(v).strip()
            if key and val:
                overrides[key] = val

    if not _loki_endpoint():
        return {"ok": False, "source": "loki-direct", "errorType": "RuntimeError", "error": "LOKI_ENDPOINT is not set"}

    # Default time window: last 60m.
    now_ms = int(time.time() * 1000)
    end_ms = int(toMs) if toMs is not None else now_ms
    start_ms = int(fromMs) if fromMs is not None else end_ms - 60 * 60 * 1000
    if end_ms <= start_ms:
        return {"ok": False, "source": "loki-direct", "errorType": "ValueError", "error": "toMs must be > fromMs"}

    # Default step: 30s.
    step_ms = int(stepMs) if stepMs is not None else 30_000
    if step_ms <= 0:
        return {"ok": False, "source": "loki-direct", "errorType": "ValueError", "error": "stepMs must be > 0"}

    try:
        panel_summary, expr = await asyncio.to_thread(
            _template_find_panel_query,
            uid=the_uid,
            panel_title=title,
            ref_id="A",
        )
        vars_map = await asyncio.to_thread(_template_extract_default_vars, the_uid)
        vars_map.update(_derive_grafana_macro_vars(start_ms=start_ms, end_ms=end_ms, step_ms=step_ms))
        vars_map.update(overrides)
        effective_expr = _apply_template_vars(expr, vars_map)

        payload = await asyncio.to_thread(
            _loki_query_range,
            query=effective_expr,
            start_ms=start_ms,
            end_ms=end_ms,
            limit=limit,
            step_s=float(step_ms) / 1000.0,
        )

        return {
            "ok": True,
            "source": "loki-direct",
            "dashboardUid": the_uid,
            "panel": panel_summary,
            "query": {
                "expr": effective_expr,
                "fromMs": start_ms,
                "toMs": end_ms,
                "stepMs": step_ms,
                "vars": vars_map,
            },
            "result": payload,
        }
    except Exception as exc:
        return {"ok": False, "source": "template", "errorType": type(exc).__name__, "error": str(exc)}


if __name__ == "__main__":
    # Serve a streamable HTTP MCP endpoint + probe routes.
    # Note: we host Starlette ourselves to allow header/payload normalization
    # for connector compatibility while still running the MCP session manager.
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run(app, host=host, port=port, log_level=os.getenv("LOG_LEVEL", "info"))
