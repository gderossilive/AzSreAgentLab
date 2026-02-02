#!/usr/bin/env bash
set -euo pipefail

# End-to-end smoke test for the Azure Managed Grafana MCP HTTP proxy (/mcp).
#
# Test Structure:
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 1. CONNECTIVITY         - Health probes, MCP endpoint reachability       ║
# ║ 2. MCP PROTOCOL          - Initialize session, list tools                 ║
# ║ 3. DATASOURCE TOOLS      - List, query (Loki + Prometheus)                ║
# ║ 4. DASHBOARD TOOLS       - Search, summary, panel data, image render      ║
# ║ 5. AZURE TOOLS (opt)     - Resource Graph, subscriptions (if enabled)     ║
# ║ 6. DIRECT PROMETHEUS     - AMW query endpoint validation                  ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
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
  --prometheus-datasource-name <n>
                           Grafana Prometheus datasource name to query via MCP (default: Prometheus (AMW))
  --dashboard-uid <uid>    Grafana dashboard UID to use for dashboard summary + panel render
                           Default: afbppudwbhl34b
  --amw-name <name>        Azure Monitor Workspace name (Microsoft.Monitor/accounts) for Prometheus query test
                           Default: auto-detect first AMW in the demo resource group
  --amw-query-endpoint <u> Azure Monitor Workspace Prometheus query endpoint
                           Default: read from AMW properties.metrics.prometheusQueryEndpoint
  --verbose                Show detailed response data
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
amw_name=""
amw_query_endpoint=""
prometheus_datasource_name="Prometheus (AMW)"
verbose="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mcp-url)
      mcp_url="${2:-}"; shift 2 ;;
    --subscription-id)
      subscription_id="${2:-}"; shift 2 ;;
    --resource-id)
      resource_id="${2:-}"; shift 2 ;;
    --prometheus-datasource-name)
      prometheus_datasource_name="${2:-}"; shift 2 ;;
    --dashboard-uid)
      dashboard_uid="${2:-}"; shift 2 ;;
    --amw-name)
      amw_name="${2:-}"; shift 2 ;;
    --amw-query-endpoint)
      amw_query_endpoint="${2:-}"; shift 2 ;;
    --verbose)
      verbose="true"; shift ;;
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

# Best-effort resolve AMW Prometheus query endpoint for the Prometheus API test.
if [[ -z "$amw_query_endpoint" ]]; then
  if command -v az >/dev/null 2>&1 && [[ -f "$config_path" ]]; then
    rg_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ResourceGroupName'])" 2>/dev/null || true)"
    if [[ -n "$rg_name" ]] && az account show >/dev/null 2>&1; then
      if [[ -z "$amw_name" ]]; then
        amw_name="$(az resource list -g "$rg_name" --resource-type Microsoft.Monitor/accounts --query "[0].name" -o tsv 2>/dev/null || true)"
      fi
      if [[ -n "$amw_name" ]]; then
        amw_query_endpoint="$(az resource show -g "$rg_name" -n "$amw_name" --resource-type Microsoft.Monitor/accounts --query properties.metrics.prometheusQueryEndpoint -o tsv 2>/dev/null || true)"
      fi
    fi
  fi
fi

if [[ -z "$mcp_url" ]]; then
  echo "Missing MCP endpoint. Provide --mcp-url or set MCP_URL." >&2
  exit 2
fi

python3 - "$mcp_url" "$subscription_id" "$resource_id" "$dashboard_uid" "$amw_query_endpoint" "$prometheus_datasource_name" "$verbose" <<'PY'
import json
import sys
import time
import subprocess
import urllib.parse
import urllib.error
import urllib.request
from typing import Any, Dict, List, Optional, Tuple
from dataclasses import dataclass

mcp_url = sys.argv[1].rstrip('/')
subscription_id = (sys.argv[2] or '').strip()
resource_id = (sys.argv[3] or '').strip()
dashboard_uid = (sys.argv[4] or '').strip()
amw_query_endpoint = (sys.argv[5] or '').strip() if len(sys.argv) > 5 else ''
prometheus_datasource_name = (sys.argv[6] or '').strip() if len(sys.argv) > 6 else 'Prometheus (AMW)'
verbose = (sys.argv[7] or '').strip().lower() == 'true' if len(sys.argv) > 7 else False


# ============================================================================
# Output Formatting
# ============================================================================

class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BOLD = '\033[1m'
    DIM = '\033[2m'
    RESET = '\033[0m'


def section(title: str) -> None:
    """Print a section header."""
    width = 75
    print()
    print(f"{Colors.BOLD}{Colors.BLUE}{'═' * width}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}  {title}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{'═' * width}{Colors.RESET}")


def subsection(title: str) -> None:
    """Print a subsection header."""
    print(f"\n{Colors.CYAN}── {title} ──{Colors.RESET}")


def log_ok(msg: str) -> None:
    print(f"  {Colors.GREEN}✓{Colors.RESET} {msg}")


def log_fail(msg: str) -> None:
    print(f"  {Colors.RED}✗{Colors.RESET} {msg}")


def log_skip(msg: str) -> None:
    print(f"  {Colors.YELLOW}○{Colors.RESET} {Colors.DIM}{msg}{Colors.RESET}")


def log_info(msg: str) -> None:
    print(f"  {Colors.DIM}ℹ{Colors.RESET} {msg}")


def log_detail(msg: str) -> None:
    if verbose:
        print(f"    {Colors.DIM}{msg}{Colors.RESET}")


# ============================================================================
# Test Result Tracking
# ============================================================================

@dataclass
class TestResult:
    name: str
    category: str
    passed: bool
    duration_ms: float = 0.0
    source: str = ""
    details: str = ""
    skipped: bool = False
    skip_reason: str = ""


test_results: List[TestResult] = []


def record_result(result: TestResult) -> None:
    test_results.append(result)
    if result.skipped:
        log_skip(f"{result.name}: {result.skip_reason}")
    elif result.passed:
        src = f" [{result.source}]" if result.source else ""
        dur = f" ({result.duration_ms:.0f}ms)" if result.duration_ms > 0 else ""
        log_ok(f"{result.name}{src}{dur}")
        if result.details:
            log_detail(result.details)
    else:
        log_fail(f"{result.name}: {result.details}")


# ============================================================================
# HTTP and MCP Helpers
# ============================================================================

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


def _short(obj: Any, limit: int = 300) -> str:
    try:
        s = json.dumps(obj, ensure_ascii=False)
    except Exception:
        s = repr(obj)
    if len(s) > limit:
        return s[:limit] + '…'
    return s


def _az_access_token(resource: str) -> Optional[str]:
    try:
        out = subprocess.check_output(
            ['az', 'account', 'get-access-token', '--resource', resource, '--query', 'accessToken', '-o', 'tsv'],
            stderr=subprocess.DEVNULL,
        )
        token = out.decode('utf-8').strip()
        return token or None
    except Exception:
        return None


def _prom_query(endpoint: str, expr: str) -> Tuple[int, Any]:
    token = _az_access_token('https://prometheus.monitor.azure.com')
    if not token:
        return 0, {'_error': 'Unable to obtain Azure token (need az login + RBAC to query AMW)'}

    base = endpoint.rstrip('/')
    qs = urllib.parse.urlencode({'query': expr})
    url = f"{base}/api/v1/query?{qs}"
    status, _headers, payload = _http(
        'GET', url,
        headers={'accept': 'application/json', 'authorization': f'Bearer {token}'},
        timeout_s=30,
    )
    return status, _json_loads_maybe(payload)


# ============================================================================
# MCP Session Management
# ============================================================================

session_id: str = ""
req_id_counter: int = 10


def mcp_call(method: str, params: Dict[str, Any]) -> Tuple[bool, Any, float]:
    global req_id_counter
    req_id_counter += 1
    
    start = time.time()
    status, headers, payload = _http(
        'POST', mcp_url,
        headers={
            'accept': 'application/json',
            'content-type': 'application/json',
            'mcp-session-id': session_id,
        },
        json_body={'jsonrpc': '2.0', 'id': req_id_counter, 'method': method, 'params': params},
        timeout_s=90,
    )
    duration_ms = (time.time() - start) * 1000
    
    obj = _json_loads_maybe(payload)
    if status != 200:
        return False, {'status': status, 'headers': headers, 'body': obj}, duration_ms
    if isinstance(obj, dict) and 'error' in obj:
        return False, obj, duration_ms
    return True, obj, duration_ms


def tool_call(name: str, args: Dict[str, Any]) -> Tuple[bool, Any, float, str]:
    """Call an MCP tool and return (success, response, duration_ms, source)."""
    ok, resp, duration_ms = mcp_call('tools/call', {'name': name, 'arguments': args})
    
    source = ""
    if ok and isinstance(resp, dict):
        result = resp.get('result')
        if isinstance(result, dict):
            if result.get('isError') is True:
                return False, result, duration_ms, source
            sc = result.get('structuredContent')
            if isinstance(sc, dict):
                if sc.get('ok') is False:
                    return False, sc, duration_ms, source
                source = sc.get('source', '')
            return True, resp, duration_ms, source
    return ok, resp, duration_ms, source


# ============================================================================
# Result Extraction Helpers
# ============================================================================

def _sc_from_resp(resp: Any) -> Optional[Dict[str, Any]]:
    if not isinstance(resp, dict):
        return None
    result = resp.get('result')
    if not isinstance(result, dict):
        return None
    sc = result.get('structuredContent')
    return sc if isinstance(sc, dict) else None


def _datasource_names(resp: Any) -> List[str]:
    sc = _sc_from_resp(resp)
    if not sc:
        return []
    dss = sc.get('datasources')
    if not isinstance(dss, list):
        return []
    return [ds.get('name') for ds in dss if isinstance(ds, dict) and ds.get('name')]


def _panel_count(resp: Any) -> int:
    sc = _sc_from_resp(resp)
    if not sc:
        return 0
    panels = sc.get('panels')
    return len(panels) if isinstance(panels, list) else 0


def _pick_panel_id(resp: Any) -> Optional[int]:
    sc = _sc_from_resp(resp)
    if not sc:
        return None
    panels = sc.get('panels')
    if not isinstance(panels, list):
        return None
    for p in panels:
        if isinstance(p, dict) and p.get('renderable') is True:
            pid = p.get('id')
            try:
                if pid is not None:
                    return int(pid)
            except Exception:
                continue
    return None


def _query_result_count(resp: Any) -> int:
    sc = _sc_from_resp(resp)
    if not sc:
        return 0
    result = sc.get('result')
    if isinstance(result, dict):
        data = result.get('data')
        if isinstance(data, dict):
            res = data.get('result')
            if isinstance(res, list):
                return len(res)
    return 0


# ============================================================================
# Test Implementation
# ============================================================================

results_cache: Dict[str, Any] = {}
discovered_tools: Dict[str, Dict[str, Any]] = {}


def test_connectivity() -> int:
    """Test 1: Connectivity - Health probes and MCP endpoint reachability."""
    section("1. CONNECTIVITY")
    failures = 0
    base_url = mcp_url.replace('/mcp', '')
    
    # Health endpoints
    subsection("Health Endpoints")
    for path in ('/', '/healthz'):
        start = time.time()
        status, _, payload = _http('GET', base_url + path, headers={'accept': 'application/json'}, timeout_s=20)
        duration_ms = (time.time() - start) * 1000
        obj = _json_loads_maybe(payload)
        ok = status == 200 and isinstance(obj, dict)
        
        record_result(TestResult(
            name=f"GET {path}",
            category="connectivity",
            passed=ok,
            duration_ms=duration_ms,
            details=_short(obj) if not ok else "",
        ))
        if not ok:
            failures += 1
    
    # MCP connector compatibility probes
    subsection("MCP Connector Compatibility")
    
    # GET /mcp without session (should return 200 for connector validation)
    status, _, payload = _http('GET', mcp_url, headers={'accept': 'application/json'}, timeout_s=20)
    record_result(TestResult(
        name="GET /mcp (no session)",
        category="connectivity",
        passed=status == 200,
        details=f"status={status}" if status != 200 else "",
    ))
    
    # DELETE /mcp without session (should return 200 for connector validation)
    status, _, payload = _http('DELETE', mcp_url, headers={'accept': 'application/json'}, timeout_s=20)
    record_result(TestResult(
        name="DELETE /mcp (no session)",
        category="connectivity",
        passed=status == 200,
        details=f"status={status}" if status != 200 else "",
    ))
    
    return failures


def test_mcp_protocol() -> int:
    """Test 2: MCP Protocol - Initialize session and list tools."""
    global session_id, discovered_tools
    section("2. MCP PROTOCOL")
    failures = 0
    
    subsection("Session Initialization")
    
    init_req = {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
            'protocolVersion': '2025-11-25',
            'capabilities': {},
            'clientInfo': {'name': 'grafana-mcp-e2e-test', 'version': '1.0'},
        },
    }
    
    start = time.time()
    status, headers, payload = _http(
        'POST', mcp_url,
        headers={'accept': 'application/json', 'content-type': 'application/json'},
        json_body=init_req,
        timeout_s=60,
    )
    duration_ms = (time.time() - start) * 1000
    
    init_obj = _json_loads_maybe(payload)
    session_id = headers.get('mcp-session-id', '')
    
    ok = status == 200 and session_id and isinstance(init_obj, dict) and 'error' not in init_obj
    record_result(TestResult(
        name="Initialize MCP session",
        category="protocol",
        passed=ok,
        duration_ms=duration_ms,
        details=f"session_id={session_id[:16]}..." if ok else f"status={status}, error={_short(init_obj)}",
    ))
    
    if not ok:
        log_fail("Cannot proceed without session. Exiting.")
        sys.exit(2)
    
    # List tools
    subsection("Tool Discovery")
    
    ok, tools_list, duration_ms = mcp_call('tools/list', {})
    if not ok:
        record_result(TestResult(
            name="List MCP tools",
            category="protocol",
            passed=False,
            duration_ms=duration_ms,
            details=_short(tools_list),
        ))
        log_fail("Cannot proceed without tools. Exiting.")
        sys.exit(2)
    
    tools = ((tools_list or {}).get('result') or {}).get('tools')
    if not isinstance(tools, list):
        log_fail("tools/list result.tools missing. Exiting.")
        sys.exit(2)
    
    for t in tools:
        if isinstance(t, dict) and isinstance(t.get('name'), str):
            discovered_tools[t['name']] = t
    
    record_result(TestResult(
        name="List MCP tools",
        category="protocol",
        passed=True,
        duration_ms=duration_ms,
        details=f"discovered {len(discovered_tools)} tools",
    ))
    
    # Show discovered tools
    log_info(f"Tools: {', '.join(sorted(discovered_tools.keys()))}")
    
    return failures


def test_datasource_tools() -> int:
    """Test 3: Datasource Tools - List and query datasources."""
    section("3. DATASOURCE TOOLS")
    failures = 0
    
    # 3.1 List datasources
    subsection("Datasource List")
    
    if 'amgmcp_datasource_list' not in discovered_tools:
        record_result(TestResult(
            name="amgmcp_datasource_list",
            category="datasource",
            passed=False,
            skipped=True,
            skip_reason="tool not available",
        ))
    else:
        ok, resp, duration_ms, source = tool_call('amgmcp_datasource_list', {})
        results_cache['datasource_list'] = resp
        ds_names = _datasource_names(resp)
        
        record_result(TestResult(
            name="amgmcp_datasource_list",
            category="datasource",
            passed=ok,
            duration_ms=duration_ms,
            source=source,
            details=f"datasources: {', '.join(ds_names)}" if ok else _short(resp),
        ))
        if not ok:
            failures += 1
        
        # Test cache behavior (second call should be fast)
        ok2, resp2, duration_ms2, source2 = tool_call('amgmcp_datasource_list', {})
        record_result(TestResult(
            name="amgmcp_datasource_list (cached)",
            category="datasource",
            passed=ok2,
            duration_ms=duration_ms2,
            source=source2,
            details="cache hit verified" if duration_ms2 < duration_ms * 0.8 else "",
        ))
        if not ok2:
            failures += 1
    
    # 3.2 Query Loki datasource
    subsection("Loki Query")
    
    if 'amgmcp_query_datasource' not in discovered_tools:
        record_result(TestResult(
            name="amgmcp_query_datasource (Loki)",
            category="datasource",
            passed=False,
            skipped=True,
            skip_reason="tool not available",
        ))
    else:
        end_ms = _now_ms()
        start_ms = end_ms - 15 * 60 * 1000
        
        ok, resp, duration_ms, source = tool_call('amgmcp_query_datasource', {
            'datasourceName': 'Loki (grocery)',
            'query': '{app="grocery-api"} | json',
            'limit': 5,
            'fromMs': start_ms,
            'toMs': end_ms,
        })
        results_cache['loki_query'] = resp
        
        record_result(TestResult(
            name="amgmcp_query_datasource (Loki)",
            category="datasource",
            passed=ok,
            duration_ms=duration_ms,
            source=source,
            details="" if ok else _short(resp),
        ))
        if not ok:
            failures += 1
    
    # 3.3 Query Prometheus datasource
    subsection("Prometheus Query (via MCP)")
    
    if 'amgmcp_query_datasource' not in discovered_tools:
        record_result(TestResult(
            name="amgmcp_query_datasource (Prometheus)",
            category="datasource",
            passed=False,
            skipped=True,
            skip_reason="tool not available",
        ))
    elif not prometheus_datasource_name:
        record_result(TestResult(
            name="amgmcp_query_datasource (Prometheus)",
            category="datasource",
            passed=False,
            skipped=True,
            skip_reason="missing --prometheus-datasource-name",
        ))
    else:
        end_ms = _now_ms()
        start_ms = end_ms - 15 * 60 * 1000
        
        ok, resp, duration_ms, source = tool_call('amgmcp_query_datasource', {
            'datasourceName': prometheus_datasource_name,
            'expr': 'up{job="ca-api"}',
            'fromMs': start_ms,
            'toMs': end_ms,
        })
        results_cache['prom_query'] = resp
        result_count = _query_result_count(resp)
        
        record_result(TestResult(
            name="amgmcp_query_datasource (Prometheus)",
            category="datasource",
            passed=ok,
            duration_ms=duration_ms,
            source=source,
            details=f"results={result_count}" if ok else _short(resp),
        ))
        if not ok:
            failures += 1
    
    return failures


def test_dashboard_tools() -> int:
    """Test 4: Dashboard Tools - Search, summary, panel data, image render."""
    section("4. DASHBOARD TOOLS")
    failures = 0
    
    # 4.1 Dashboard search
    subsection("Dashboard Search")
    
    if 'amgmcp_dashboard_search' not in discovered_tools:
        record_result(TestResult(
            name="amgmcp_dashboard_search",
            category="dashboard",
            passed=False,
            skipped=True,
            skip_reason="tool not available",
        ))
    else:
        ok, resp, duration_ms, source = tool_call('amgmcp_dashboard_search', {
            'query': 'Grocery App - SRE Overview',
        })
        results_cache['dashboard_search'] = resp
        
        record_result(TestResult(
            name="amgmcp_dashboard_search",
            category="dashboard",
            passed=ok,
            duration_ms=duration_ms,
            source=source,
            details="" if ok else _short(resp),
        ))
        if not ok:
            failures += 1
    
    # 4.2 Dashboard summary
    subsection("Dashboard Summary")
    
    if 'amgmcp_get_dashboard_summary' not in discovered_tools:
        record_result(TestResult(
            name="amgmcp_get_dashboard_summary",
            category="dashboard",
            passed=False,
            skipped=True,
            skip_reason="tool not available",
        ))
    elif not dashboard_uid:
        record_result(TestResult(
            name="amgmcp_get_dashboard_summary",
            category="dashboard",
            passed=False,
            skipped=True,
            skip_reason="missing --dashboard-uid",
        ))
    else:
        ok, resp, duration_ms, source = tool_call('amgmcp_get_dashboard_summary', {
            'dashboardUid': dashboard_uid,
        })
        results_cache['dashboard_summary'] = resp
        panel_count = _panel_count(resp)
        
        record_result(TestResult(
            name="amgmcp_get_dashboard_summary",
            category="dashboard",
            passed=ok,
            duration_ms=duration_ms,
            source=source,
            details=f"panels={panel_count}" if ok else _short(resp),
        ))
        if not ok:
            failures += 1
    
    # 4.3 Panel data (Loki panel)
    subsection("Panel Data (Loki)")
    
    if 'amgmcp_get_panel_data' not in discovered_tools:
        record_result(TestResult(
            name="amgmcp_get_panel_data (Loki)",
            category="dashboard",
            passed=False,
            skipped=True,
            skip_reason="tool not available",
        ))
    elif not dashboard_uid:
        record_result(TestResult(
            name="amgmcp_get_panel_data (Loki)",
            category="dashboard",
            passed=False,
            skipped=True,
            skip_reason="missing --dashboard-uid",
        ))
    else:
        end_ms = _now_ms()
        start_ms = end_ms - 15 * 60 * 1000
        
        ok, resp, duration_ms, source = tool_call('amgmcp_get_panel_data', {
            'dashboardUid': dashboard_uid,
            'panelTitle': 'Error rate (errors/s)',
            'fromMs': start_ms,
            'toMs': end_ms,
            'stepMs': 30_000,
        })
        results_cache['panel_data_loki'] = resp
        
        record_result(TestResult(
            name="amgmcp_get_panel_data (Loki panel)",
            category="dashboard",
            passed=ok,
            duration_ms=duration_ms,
            source=source,
            details="" if ok else _short(resp),
        ))
        if not ok:
            failures += 1
    
    # 4.4 Panel data (Prometheus panel)
    subsection("Panel Data (Prometheus)")
    
    if 'amgmcp_get_panel_data' not in discovered_tools:
        record_result(TestResult(
            name="amgmcp_get_panel_data (Prometheus)",
            category="dashboard",
            passed=False,
            skipped=True,
            skip_reason="tool not available",
        ))
    elif not dashboard_uid:
        record_result(TestResult(
            name="amgmcp_get_panel_data (Prometheus)",
            category="dashboard",
            passed=False,
            skipped=True,
            skip_reason="missing --dashboard-uid",
        ))
    else:
        end_ms = _now_ms()
        start_ms = end_ms - 15 * 60 * 1000
        
        # Try multiple panel name variants
        ok = False
        resp = None
        duration_ms = 0
        source = ""
        for panel_name in ('Requests/sec (API)', 'Requests/sec', 'Request Rate'):
            ok, resp, duration_ms, source = tool_call('amgmcp_get_panel_data', {
                'dashboardUid': dashboard_uid,
                'panelTitle': panel_name,
                'fromMs': start_ms,
                'toMs': end_ms,
                'stepMs': 30_000,
            })
            if ok:
                results_cache['panel_data_prom'] = resp
                break
        
        record_result(TestResult(
            name="amgmcp_get_panel_data (Prometheus panel)",
            category="dashboard",
            passed=ok,
            duration_ms=duration_ms,
            source=source,
            details="" if ok else _short(resp),
        ))
        if not ok:
            failures += 1
    
    # 4.5 Image render
    subsection("Image Render")
    
    if 'amgmcp_image_render' not in discovered_tools:
        record_result(TestResult(
            name="amgmcp_image_render",
            category="dashboard",
            passed=False,
            skipped=True,
            skip_reason="tool not available",
        ))
    elif not dashboard_uid:
        record_result(TestResult(
            name="amgmcp_image_render",
            category="dashboard",
            passed=False,
            skipped=True,
            skip_reason="missing --dashboard-uid",
        ))
    else:
        end_ms = _now_ms()
        start_ms = end_ms - 60 * 60 * 1000
        
        args = {
            'dashboardUid': dashboard_uid,
            'fromMs': start_ms,
            'toMs': end_ms,
            'width': 800,
            'height': 400,
        }
        
        # Try to use a specific panel if we have summary
        panel_id = _pick_panel_id(results_cache.get('dashboard_summary'))
        if panel_id is not None:
            args['panelId'] = panel_id
        
        ok, resp, duration_ms, source = tool_call('amgmcp_image_render', args)
        
        # Check if we got image data
        sc = _sc_from_resp(resp)
        has_image = sc and isinstance(sc.get('imageBase64'), str) and len(sc.get('imageBase64', '')) > 100
        
        record_result(TestResult(
            name="amgmcp_image_render",
            category="dashboard",
            passed=ok,
            duration_ms=duration_ms,
            source=source,
            details=f"bytes={sc.get('bytes', 'N/A')}" if has_image else ("placeholder" if source == "placeholder" else _short(resp)),
        ))
        if not ok:
            failures += 1
    
    return failures


def test_azure_tools() -> int:
    """Test 5: Azure Tools - Resource Graph, subscriptions (if enabled)."""
    section("5. AZURE TOOLS (Optional)")
    failures = 0
    
    # These tools are disabled by default (DISABLE_AMGMCP_AZURE_TOOLS=true)
    azure_tools = ['amgmcp_query_azure_subscriptions', 'amgmcp_query_resource_graph', 'amgmcp_query_resource_log']
    available = [t for t in azure_tools if t in discovered_tools]
    
    if not available:
        log_info("Azure tools are disabled (DISABLE_AMGMCP_AZURE_TOOLS=true). This is expected.")
        return 0
    
    subsection("Azure Subscriptions")
    
    if 'amgmcp_query_azure_subscriptions' in discovered_tools:
        ok, resp, duration_ms, source = tool_call('amgmcp_query_azure_subscriptions', {})
        record_result(TestResult(
            name="amgmcp_query_azure_subscriptions",
            category="azure",
            passed=ok,
            duration_ms=duration_ms,
            source=source,
            details="" if ok else _short(resp),
        ))
        if not ok:
            failures += 1
    
    subsection("Resource Graph Query")
    
    if 'amgmcp_query_resource_graph' in discovered_tools:
        if not subscription_id:
            record_result(TestResult(
                name="amgmcp_query_resource_graph",
                category="azure",
                passed=False,
                skipped=True,
                skip_reason="missing --subscription-id",
            ))
        else:
            ok, resp, duration_ms, source = tool_call('amgmcp_query_resource_graph', {
                'query': 'Resources | project name, type | take 1',
                'subscriptions': [subscription_id],
            })
            record_result(TestResult(
                name="amgmcp_query_resource_graph",
                category="azure",
                passed=ok,
                duration_ms=duration_ms,
                source=source,
                details="" if ok else _short(resp),
            ))
            if not ok:
                failures += 1
    
    return failures


def test_direct_prometheus() -> int:
    """Test 6: Direct Prometheus - AMW query endpoint validation."""
    section("6. DIRECT PROMETHEUS (AMW)")
    failures = 0
    
    if not amw_query_endpoint:
        log_info("AMW query endpoint not configured. Skipping direct Prometheus tests.")
        log_info("Pass --amw-query-endpoint or ensure demo-config.json + az login")
        return 0
    
    subsection("PromQL Queries via AMW")
    
    queries = [
        ('up{job="ca-api"}', 'API container scrape target'),
        ('probe_success{job="blackbox-http"}', 'Blackbox probe success'),
    ]
    
    for expr, description in queries:
        start = time.time()
        status, obj = _prom_query(amw_query_endpoint, expr)
        duration_ms = (time.time() - start) * 1000
        
        ok = False
        result_count = 0
        if status == 200 and isinstance(obj, dict):
            data = obj.get('data')
            if isinstance(data, dict):
                result = data.get('result')
                if isinstance(result, list):
                    result_count = len(result)
                    ok = result_count > 0
        
        record_result(TestResult(
            name=f"PromQL: {expr}",
            category="prometheus",
            passed=ok,
            duration_ms=duration_ms,
            details=f"{description}, results={result_count}" if ok else f"status={status}, {_short(obj)}",
        ))
        
        if not ok:
            failures += 1
            log_info("If RBAC was just granted, allow ~30min for propagation.")
    
    return failures


def print_summary() -> None:
    """Print test summary."""
    section("TEST SUMMARY")
    
    categories = {}
    for r in test_results:
        if r.category not in categories:
            categories[r.category] = {'passed': 0, 'failed': 0, 'skipped': 0}
        if r.skipped:
            categories[r.category]['skipped'] += 1
        elif r.passed:
            categories[r.category]['passed'] += 1
        else:
            categories[r.category]['failed'] += 1
    
    total_passed = sum(c['passed'] for c in categories.values())
    total_failed = sum(c['failed'] for c in categories.values())
    total_skipped = sum(c['skipped'] for c in categories.values())
    
    print()
    print(f"  {'Category':<20} {'Passed':>8} {'Failed':>8} {'Skipped':>8}")
    print(f"  {'-' * 20} {'-' * 8} {'-' * 8} {'-' * 8}")
    
    for cat, counts in sorted(categories.items()):
        passed = f"{Colors.GREEN}{counts['passed']}{Colors.RESET}" if counts['passed'] else "0"
        failed = f"{Colors.RED}{counts['failed']}{Colors.RESET}" if counts['failed'] else "0"
        skipped = f"{Colors.YELLOW}{counts['skipped']}{Colors.RESET}" if counts['skipped'] else "0"
        print(f"  {cat:<20} {passed:>17} {failed:>17} {skipped:>17}")
    
    print(f"  {'-' * 20} {'-' * 8} {'-' * 8} {'-' * 8}")
    
    total_passed_str = f"{Colors.GREEN}{total_passed}{Colors.RESET}" if total_passed else "0"
    total_failed_str = f"{Colors.RED}{total_failed}{Colors.RESET}" if total_failed else "0"
    total_skipped_str = f"{Colors.YELLOW}{total_skipped}{Colors.RESET}" if total_skipped else "0"
    print(f"  {'TOTAL':<20} {total_passed_str:>17} {total_failed_str:>17} {total_skipped_str:>17}")
    
    print()
    if total_failed == 0:
        print(f"{Colors.BOLD}{Colors.GREEN}═══════════════════════════════════════════════════════════════════════════{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.GREEN}  ✓ ALL TESTS PASSED{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.GREEN}═══════════════════════════════════════════════════════════════════════════{Colors.RESET}")
    else:
        print(f"{Colors.BOLD}{Colors.RED}═══════════════════════════════════════════════════════════════════════════{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.RED}  ✗ {total_failed} TEST(S) FAILED{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.RED}═══════════════════════════════════════════════════════════════════════════{Colors.RESET}")


# ============================================================================
# Main Execution
# ============================================================================

def main() -> int:
    print()
    print(f"{Colors.BOLD}MCP Server End-to-End Test Suite{Colors.RESET}")
    print(f"{Colors.DIM}Testing: {mcp_url}{Colors.RESET}")
    if amw_query_endpoint:
        print(f"{Colors.DIM}AMW Endpoint: {amw_query_endpoint}{Colors.RESET}")
    print(f"{Colors.DIM}Dashboard UID: {dashboard_uid}{Colors.RESET}")
    print(f"{Colors.DIM}Prometheus DS: {prometheus_datasource_name}{Colors.RESET}")
    
    total_failures = 0
    
    total_failures += test_connectivity()
    total_failures += test_mcp_protocol()
    total_failures += test_datasource_tools()
    total_failures += test_dashboard_tools()
    total_failures += test_azure_tools()
    total_failures += test_direct_prometheus()
    
    # Session cleanup
    _http('DELETE', mcp_url, headers={'accept': 'application/json', 'mcp-session-id': session_id}, timeout_s=10)
    
    print_summary()
    
    return 1 if total_failures > 0 else 0


if __name__ == '__main__':
    sys.exit(main())
PY
