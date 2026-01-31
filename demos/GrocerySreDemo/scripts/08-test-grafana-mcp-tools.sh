#!/usr/bin/env bash
set -euo pipefail

# End-to-end smoke test for the Azure Managed Grafana MCP HTTP proxy (/mcp).
# - Initializes an MCP session
# - Lists tools
# - Calls each tool with safe, minimal inputs
#
# No secrets are printed or written.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_root="$(cd "$script_dir/.." && pwd)"
config_path="$demo_root/demo-config.json"

usage() {
  cat <<'USAGE'
Usage:
    ./scripts/08-test-grafana-mcp-tools.sh [options]

Options:
  --mcp-url <url>          MCP endpoint URL (default: auto-detect or env MCP_URL)
                           Example: https://<fqdn>/mcp
  --subscription-id <id>   Subscription id for Resource Graph queries (default: env AZURE_SUBSCRIPTION_ID)
  --resource-id <id>       Resource id for resource-log queries (optional; if required, tool will be skipped)
    --dashboard-uid <uid>     Grafana dashboard UID to use for dashboard summary + panel render
                                                        Default: afbppudwbhl34b
  -h|--help                Show help

Auto-detect behavior:
  - If --mcp-url is omitted and demo-config.json exists and you're logged into Azure CLI,
    the script will try to resolve the Container App 'ca-mcp-amg-proxy' FQDN.

Exit codes:
  0 = all executed tool calls succeeded (skipped tools don't fail the run)
  1 = one or more executed tool calls failed
USAGE
}

mcp_url="${MCP_URL:-${MCP_URL:-}}"
subscription_id="${AZURE_SUBSCRIPTION_ID:-${SUBSCRIPTION_ID:-}}"
resource_id=""
dashboard_uid="afbppudwbhl34b"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mcp-url)
      mcp_url="${2:-}"; shift 2 ;;
    --subscription-id)
      subscription_id="${2:-}"; shift 2 ;;
    --resource-id)
      resource_id="${2:-}"; shift 2 ;;
        --dashboard-uid)
            dashboard_uid="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

command -v python3 >/dev/null 2>&1 || { echo "python3 not found" >&2; exit 2; }

if [[ -z "$mcp_url" ]]; then
  if command -v az >/dev/null 2>&1 && [[ -f "$config_path" ]]; then
    # Best-effort auto-resolve deployed proxy.
    rg_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ResourceGroupName'])" 2>/dev/null || true)"
    if [[ -n "$rg_name" ]] && az account show >/dev/null 2>&1; then
      fqdn="$(az containerapp show -g "$rg_name" -n "ca-mcp-amg-proxy" --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || true)"
      if [[ -n "$fqdn" ]]; then
        mcp_url="https://${fqdn}/mcp"
      fi
    fi
  fi
fi

if [[ -z "$mcp_url" ]]; then
  echo "Missing MCP endpoint. Provide --mcp-url or set MCP_URL." >&2
  exit 2
fi

python3 - "$mcp_url" "$subscription_id" "$resource_id" "$dashboard_uid" <<'PY'
import json
import sys
import time
import urllib.error
import urllib.request
from typing import Any, Dict, Optional, Tuple

mcp_url = sys.argv[1].rstrip('/')
subscription_id = (sys.argv[2] or '').strip()
resource_id = (sys.argv[3] or '').strip()
dashboard_uid = (sys.argv[4] or '').strip()


def _now_ms() -> int:
    return int(time.time() * 1000)


def _http(method: str, url: str, *, headers: Optional[Dict[str, str]] = None, json_body: Any = None, timeout_s: int = 30) -> Tuple[int, Dict[str, str], bytes]:
    data = None
    hdrs = dict(headers or {})
    if json_body is not None:
        body = json.dumps(json_body, separators=(',', ':')).encode('utf-8')
        data = body
        hdrs.setdefault('content-type', 'application/json')
        hdrs.setdefault('accept', 'application/json')
    req = urllib.request.Request(url, data=data, method=method, headers=hdrs)
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            status = int(resp.status)
            resp_headers = {k.lower(): v for k, v in resp.headers.items()}
            payload = resp.read() or b''
            return status, resp_headers, payload
    except urllib.error.HTTPError as e:
        status = int(e.code)
        resp_headers = {k.lower(): v for k, v in e.headers.items()}
        payload = e.read() or b''
        return status, resp_headers, payload
    except TimeoutError as e:
        body = json.dumps({'_errorType': 'TimeoutError', '_error': str(e)}, separators=(',', ':')).encode('utf-8')
        return 0, {}, body
    except urllib.error.URLError as e:
        body = json.dumps({'_errorType': 'URLError', '_error': str(e)}, separators=(',', ':')).encode('utf-8')
        return 0, {}, body


def _json_loads_maybe(payload: bytes) -> Any:
    if not payload:
        return None
    try:
        return json.loads(payload.decode('utf-8'))
    except Exception:
        return {'_raw': payload[:512].decode('utf-8', errors='replace')}


def _short(obj: Any, limit: int = 700) -> str:
    try:
        s = json.dumps(obj, ensure_ascii=False)
    except Exception:
        s = repr(obj)
    if len(s) > limit:
        return s[:limit] + '…'
    return s


def _mcp_call(session_id: str, req_id: int, method: str, params: Dict[str, Any]) -> Tuple[bool, Any]:
    status, headers, payload = _http(
        'POST',
        mcp_url,
        headers={
            'accept': 'application/json',
            'content-type': 'application/json',
            'mcp-session-id': session_id,
        },
        json_body={'jsonrpc': '2.0', 'id': req_id, 'method': method, 'params': params},
        timeout_s=60,
    )
    obj = _json_loads_maybe(payload)
    if status != 200:
        return False, {'status': status, 'headers': headers, 'body': obj}
    if isinstance(obj, dict) and 'error' in obj:
        return False, obj
    return True, obj


failures = 0

print(f"[INFO] MCP URL: {mcp_url}")

# Probe routes
for path in ('/', '/healthz'):
    status, _, payload = _http('GET', mcp_url.replace('/mcp', '') + path, headers={'accept': 'application/json'}, timeout_s=20)
    obj = _json_loads_maybe(payload)
    ok = status == 200 and isinstance(obj, dict) and obj.get('status', 'ok') in ('ok', 'OK')
    tag = 'OK' if ok else 'WARN'
    print(f"[{tag}] GET {path} -> {status} {_short(obj)}")

# Connector-compat probes
status, _, payload = _http('GET', mcp_url, headers={'accept': 'application/json'}, timeout_s=20)
print(f"[INFO] GET /mcp (no session, JSON) -> {status} {_short(_json_loads_maybe(payload))}")
status, _, payload = _http('DELETE', mcp_url, headers={'accept': 'application/json'}, timeout_s=20)
print(f"[INFO] DELETE /mcp (no session) -> {status} {_short(_json_loads_maybe(payload))}")

# Initialize
init_req = {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'initialize',
    'params': {
        'protocolVersion': '2025-11-25',
        'capabilities': {},
        'clientInfo': {'name': 'grafana-mcp-e2e-test', 'version': '0'},
    },
}
start = time.time()
status, headers, payload = _http(
    'POST',
    mcp_url,
    headers={'accept': 'application/json', 'content-type': 'application/json'},
    json_body=init_req,
    timeout_s=60,
)
init_obj = _json_loads_maybe(payload)
session_id = headers.get('mcp-session-id')
dt = time.time() - start
if status != 200 or not session_id or not isinstance(init_obj, dict) or 'error' in init_obj:
    print(f"[FAIL] initialize -> status={status} session_id={session_id!r} dt={dt:.2f}s body={_short(init_obj)}")
    sys.exit(2)
print(f"[OK] initialize -> session_id={session_id} dt={dt:.2f}s")

# tools/list
ok, tools_list = _mcp_call(session_id, 2, 'tools/list', {})
if not ok:
    print(f"[FAIL] tools/list -> {_short(tools_list)}")
    sys.exit(2)

tools = ((tools_list or {}).get('result') or {}).get('tools')
if not isinstance(tools, list):
    print(f"[FAIL] tools/list result.tools missing -> {_short(tools_list)}")
    sys.exit(2)

print(f"[INFO] tools discovered: {len(tools)}")

by_name: Dict[str, Dict[str, Any]] = {}
for t in tools:
    if isinstance(t, dict) and isinstance(t.get('name'), str):
        by_name[t['name']] = t

# Helpers to derive safe arguments

def _required_keys(tool: Dict[str, Any]) -> set:
    schema = tool.get('inputSchema')
    if isinstance(schema, dict):
        req = schema.get('required')
        if isinstance(req, list):
            return {x for x in req if isinstance(x, str)}
    return set()


def _pick_dashboard_uid(search_resp: Any) -> Optional[str]:
    # We don't want to depend on exact result shape; try a few common ones.
    if not isinstance(search_resp, dict):
        return None
    result = search_resp.get('result')
    if isinstance(result, dict):
        for key in ('dashboards', 'results', 'items'):
            items = result.get(key)
            if isinstance(items, list):
                for it in items:
                    if isinstance(it, dict):
                        uid = it.get('uid') or it.get('dashboardUid')
                        if isinstance(uid, str) and uid.strip():
                            return uid
    # Sometimes backend tool returns nested content arrays.
    for v in search_resp.values():
        if isinstance(v, list):
            for it in v:
                if isinstance(it, dict):
                    uid = it.get('uid')
                    if isinstance(uid, str) and uid.strip():
                        return uid
    return None


def _pick_loki_datasource_uid(ds_resp: Any) -> Optional[str]:
    if not isinstance(ds_resp, dict):
        return None
    # Proxy fast-path returns {ok: True, datasources: [...]}
    dss = ds_resp.get('datasources')
    if isinstance(dss, list):
        for ds in dss:
            if not isinstance(ds, dict):
                continue
            t = (ds.get('type') or '')
            name = (ds.get('name') or '')
            uid = ds.get('uid')
            if isinstance(uid, str) and uid.strip() and ('loki' in str(t).lower() or 'loki' in str(name).lower()):
                return uid
    # Backend tool may return different shape.
    result = ds_resp.get('result')
    if isinstance(result, dict):
        items = result.get('datasources') or result.get('items') or result.get('result')
        if isinstance(items, list):
            for ds in items:
                if not isinstance(ds, dict):
                    continue
                t = (ds.get('type') or '')
                name = (ds.get('name') or '')
                uid = ds.get('uid') or ds.get('datasourceUid')
                if isinstance(uid, str) and uid.strip() and ('loki' in str(t).lower() or 'loki' in str(name).lower()):
                    return uid
    return None


results_cache: Dict[str, Any] = {}

# Pre-run dependencies for better end-to-end coverage
# - datasource_list helps populate datasource UID for query_datasource
# - get_dashboard_summary lists panels so we can render just one panel


def _pick_panel_id(summary_tool_resp: Any) -> Optional[int]:
    if not isinstance(summary_tool_resp, dict):
        return None
    result = summary_tool_resp.get('result')
    if not isinstance(result, dict):
        return None
    sc = result.get('structuredContent')
    if not isinstance(sc, dict):
        return None
    panels = sc.get('panels')
    if not isinstance(panels, list):
        return None
    for p in panels:
        if not isinstance(p, dict):
            continue
        if p.get('renderable') is True:
            pid = p.get('id')
            try:
                if pid is not None:
                    return int(pid)
            except Exception:
                continue
    return None

def run_tool(name: str, args: Dict[str, Any], req_id: int) -> Tuple[bool, Any]:
    start_t = time.time()
    ok2, resp = _mcp_call(session_id, req_id, 'tools/call', {'name': name, 'arguments': args})
    dt2 = time.time() - start_t

    tool_ok = False
    tool_err = None
    if ok2 and isinstance(resp, dict):
        result = resp.get('result')
        if isinstance(result, dict):
            if result.get('isError') is True:
                tool_err = result
            else:
                sc = result.get('structuredContent')
                if isinstance(sc, dict) and sc.get('ok') is False:
                    tool_err = sc
                else:
                    tool_ok = True
        else:
            # Unexpected shape; treat as failure.
            tool_err = {'error': 'Missing result object'}
    else:
        tool_err = resp

    if tool_ok:
        print(f"[OK]  {name} dt={dt2:.2f}s args={_short(args, 200)}")
    else:
        print(f"[FAIL] {name} dt={dt2:.2f}s args={_short(args, 200)} resp={_short(tool_err)}")
    return tool_ok, resp


req_id = 10

# 1) datasource list
if 'amgmcp_datasource_list' in by_name:
    ok2, resp = run_tool('amgmcp_datasource_list', {}, req_id)
    req_id += 1
    results_cache['amgmcp_datasource_list'] = resp
    if not ok2:
        failures += 1

# 2) dashboard search
if 'amgmcp_dashboard_search' in by_name:
    ok2, resp = run_tool('amgmcp_dashboard_search', {'query': 'Grocery App - SRE Overview (Custom)'}, req_id)
    req_id += 1
    results_cache['amgmcp_dashboard_search'] = resp
    if not ok2:
        failures += 1

# 2b) dashboard summary (panel inventory)
if 'amgmcp_get_dashboard_summary' in by_name:
    ok2, resp = run_tool('amgmcp_get_dashboard_summary', {'dashboardUid': dashboard_uid}, req_id)
    req_id += 1
    results_cache['amgmcp_get_dashboard_summary'] = resp
    if not ok2:
        failures += 1

# 2c) panel data (query_range behind a panel)
if 'amgmcp_get_panel_data' in by_name:
    end_ms = _now_ms()
    start_ms = end_ms - 15 * 60 * 1000
    ok2, resp = run_tool(
        'amgmcp_get_panel_data',
        {
            'dashboardUid': dashboard_uid,
            'panelTitle': 'Error rate (errors/s)',
            'fromMs': start_ms,
            'toMs': end_ms,
            'stepMs': 30_000,
        },
        req_id,
    )
    req_id += 1
    results_cache['amgmcp_get_panel_data'] = resp
    if not ok2:
        failures += 1

# 3) subscription list
if 'amgmcp_query_azure_subscriptions' in by_name:
    ok2, resp = run_tool('amgmcp_query_azure_subscriptions', {}, req_id)
    req_id += 1
    results_cache['amgmcp_query_azure_subscriptions'] = resp
    if not ok2:
        failures += 1

# Now run remaining tools with best-effort inputs
for tool_name in sorted(by_name.keys()):
    if tool_name in (
        'amgmcp_datasource_list',
        'amgmcp_dashboard_search',
        'amgmcp_get_panel_data',
        'amgmcp_query_azure_subscriptions',
    ):
        continue

    tool = by_name[tool_name]
    req = _required_keys(tool)

    args: Dict[str, Any] = {}

    if tool_name == 'amgmcp_query_resource_graph':
        # Resource Graph KQL-ish; keep it tiny.
        q = 'Resources | project name, type | take 1'
        if 'query' in req or 'query' in (tool.get('inputSchema') or {}).get('properties', {}):
            args['query'] = q
        else:
            args['kql'] = q
        if 'subscriptions' in req and subscription_id:
            args['subscriptions'] = [subscription_id]
        elif 'subscriptions' in req and not subscription_id:
            print(f"[SKIP] {tool_name}: requires subscriptions; set --subscription-id")
            continue

    elif tool_name == 'amgmcp_query_resource_log':
        q = 'AzureActivity | take 1'
        # Backend may accept query or kql.
        if 'query' in req:
            args['query'] = q
        else:
            args['kql'] = q
        if 'resourceId' in req:
            if not resource_id:
                print(f"[SKIP] {tool_name}: requires resourceId; pass --resource-id")
                continue
            args['resourceId'] = resource_id

    elif tool_name == 'amgmcp_query_datasource':
        # Prefer datasourceName so this test doesn't depend on parsing datasource_list output.
        # (Assumes the demo created the Loki datasource named 'Loki (grocery)'.)
        args['datasourceName'] = 'Loki (grocery)'
        # Small, safe query and tight window.
        end_ms = _now_ms()
        start_ms = end_ms - 15 * 60 * 1000
        # Use the demo's canonical app label and a query that should be valid
        # even when there are no recent errors.
        args['query'] = '{app="grocery-api"} | json'
        args['limit'] = 5
        args['fromMs'] = start_ms
        args['toMs'] = end_ms

    elif tool_name == 'amgmcp_image_render':
        dash_uid = dashboard_uid
        if not dash_uid:
            print(f"[SKIP] {tool_name}: missing --dashboard-uid")
            continue
        end_ms = _now_ms()
        start_ms = end_ms - 60 * 60 * 1000
        args['dashboardUid'] = dash_uid
        pid = _pick_panel_id(results_cache.get('amgmcp_get_dashboard_summary'))
        if pid is not None:
            args['panelId'] = pid
        args['fromMs'] = start_ms
        args['toMs'] = end_ms
        args['width'] = 1000
        args['height'] = 500

    else:
        # Generic fallback: try empty args if nothing required.
        if req:
            print(f"[SKIP] {tool_name}: has required args {sorted(req)} (no built-in defaults)")
            continue

    ok2, _resp = run_tool(tool_name, args, req_id)
    req_id += 1
    if not ok2:
        failures += 1

# Best-effort session cleanup
_http('DELETE', mcp_url, headers={'accept': 'application/json', 'mcp-session-id': session_id}, timeout_s=10)

if failures:
    print(f"[RESULT] FAIL ({failures} tool call(s) failed)")
    sys.exit(1)

print("[RESULT] OK")
PY
