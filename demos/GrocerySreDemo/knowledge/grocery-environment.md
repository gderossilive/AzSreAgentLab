# Grocery SRE Demo Environment (Sweden Central)

This environment hosts a "Grocery" sample app on Azure Container Apps, with centralized logging in Loki, metrics in Azure Monitor Workspace (Managed Prometheus), dashboards in Managed Grafana, and an Azure SRE Agent for investigation/remediation.

---

## Current Deployment (as of 2026-02-02)

| Component | Resource Name | URL / Endpoint |
|-----------|---------------|----------------|
| **Resource Group** | `rg-grocery-sre-demo` | — |
| **Container Apps Environment** | `cae-pu3vvmgkrke3q` | — |
| **Container Registry (ACR)** | `crpu3vvmgkrke3q` | `crpu3vvmgkrke3q.azurecr.io` |
| **Grocery API** | `ca-api-pu3vvmgkrke3q` | https://ca-api-pu3vvmgkrke3q.mangoplant-51da0571.swedencentral.azurecontainerapps.io |
| **Grocery Web** | `ca-web-pu3vvmgkrke3q` | https://ca-web-pu3vvmgkrke3q.mangoplant-51da0571.swedencentral.azurecontainerapps.io |
| **Loki** | `ca-loki` | https://ca-loki.mangoplant-51da0571.swedencentral.azurecontainerapps.io |
| **Grafana MCP Proxy** | `ca-mcp-amg-proxy` | https://ca-mcp-amg-proxy.mangoplant-51da0571.swedencentral.azurecontainerapps.io/mcp |
| **Prometheus (AMW Monitoring)** | `ca-prom-amw-monitoring` | (internal scraper) |
| **Azure Monitor Workspace** | `amw-pu3vvmgkrke3q` | https://amw-pu3vvmgkrke3q-eugebsh0ekdub2ax.swedencentral.prometheus.monitor.azure.com |
| **Log Analytics Workspace** | `workspacepu3vvmgkrke3q` | — |
| **Managed Grafana** | `amg-pu3vvmgkrke3q` | https://amg-pu3vvmgkrke3q-bnenf9hdb0erh5e4.cse.grafana.azure.com |
| **SRE Agent** | `sre-agent-grocery-demo` | https://sre-agent-grocery-demo--4e739d60.6d6a35f1.swedencentral.azuresre.ai |

**Last app image tag**: `20260129083730`

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        rg-grocery-sre-demo (Sweden Central)                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐                 │
│   │  Grocery    │      │  Grocery    │      │    Loki     │                 │
│   │    Web      │─────▶│    API      │─────▶│   (logs)    │                 │
│   │ (frontend)  │      │ (backend)   │      │             │                 │
│   └─────────────┘      └──────┬──────┘      └──────┬──────┘                 │
│                               │                    │                        │
│                               │ metrics            │ LogQL                  │
│                               ▼                    ▼                        │
│   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐                 │
│   │  Prometheus │      │    Azure    │      │   Grafana   │                 │
│   │  (scraper)  │─────▶│   Monitor   │◀────▶│   MCP Proxy │                 │
│   │             │      │  Workspace  │      │             │                 │
│   └─────────────┘      └──────┬──────┘      └──────┬──────┘                 │
│                               │                    │                        │
│                               │ PromQL             │ MCP                    │
│                               ▼                    ▼                        │
│                        ┌─────────────┐      ┌─────────────┐                 │
│                        │  Managed    │      │    SRE      │                 │
│                        │   Grafana   │◀────▶│   Agent     │                 │
│                        │             │      │             │                 │
│                        └─────────────┘      └─────────────┘                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## SRE Agent Configuration

| Property | Value |
|----------|-------|
| Name | `sre-agent-grocery-demo` |
| Endpoint | https://sre-agent-grocery-demo--4e739d60.6d6a35f1.swedencentral.azuresre.ai |
| Portal URL | [Open in Azure Portal](https://ms.portal.azure.com/#view/Microsoft_Azure_PaasServerless/AgentFrameBlade.ReactView/id/%2Fsubscriptions%2F06dbbc7b-2363-4dd4-9803-95d07f1a8d3e%2FresourceGroups%2Frg-grocery-sre-demo%2Fproviders%2FMicrosoft.App%2Fagents%2Fsre-agent-grocery-demo) |
| Action Mode | `Review` (change to `Autonomous` for auto-remediation) |
| Running State | `BuildingKnowledgeGraph` (will become `Running` when ready) |

### MCP Connector for SRE Agent

The SRE Agent connects to Grafana via the **Grafana MCP Proxy**:

- **Connector URL**: `https://ca-mcp-amg-proxy.mangoplant-51da0571.swedencentral.azurecontainerapps.io/mcp`
- **Transport**: Streamable HTTP (JSON-only mode)
- **Authentication**: Managed Identity (Grafana Viewer RBAC)

> ⚠️ **Do NOT use** the Grafana UI endpoint (`https://amg-pu3vvmgkrke3q-bnenf9hdb0erh5e4.cse.grafana.azure.com`) as the connector URL.

---

## Observability Stack

### Logs (Loki)

- **Endpoint**: `https://ca-loki.mangoplant-51da0571.swedencentral.azurecontainerapps.io`
- **Primary label**: `app="grocery-api"`
- **Query reference**: See [loki-queries.md](loki-queries.md)

### Metrics (Prometheus / AMW)

- **AMW Endpoint**: `https://amw-pu3vvmgkrke3q-eugebsh0ekdub2ax.swedencentral.prometheus.monitor.azure.com`
- **Jobs**: `ca-api` (Grocery API), `blackbox-http` (availability probes)
- **Metric prefix**: `grocery_`
- **Query reference**: See [amw-queries.md](amw-queries.md)

### Dashboards (Managed Grafana)

- **Grafana URL**: https://amg-pu3vvmgkrke3q-bnenf9hdb0erh5e4.cse.grafana.azure.com
- **Custom Dashboard**: `Grocery App - SRE Overview (Custom)` (UID: `afbppudwbhl34b`)
- **Datasources**:
  - `Loki (grocery)` — for log panels
  - `Prometheus (AMW)` — for metric panels

---

## Grafana MCP Proxy

The proxy (`ca-mcp-amg-proxy`) exposes these MCP tools to the SRE Agent:

| Tool | Description |
|------|-------------|
| `amgmcp_datasource_list` | List available datasources (Loki, Prometheus) |
| `amgmcp_query_datasource` | Execute LogQL or PromQL queries |
| `amgmcp_dashboard_search` | Search dashboards by title/tag |
| `amgmcp_get_dashboard_summary` | Get dashboard metadata and panel list |
| `amgmcp_get_panel_data` | Retrieve panel data by title |
| `amgmcp_image_render` | Render dashboard/panel as PNG |

**Test the MCP proxy**:
```bash
cd demos/GrocerySreDemo
./scripts/08-test-grafana-mcp-tools.sh
```

---

## Alerts

| Alert Name | Type | Trigger |
|------------|------|---------|
| **Grocery API - Supplier rate limit (SUPPLIER_RATE_LIMIT_429)** | Scheduled Query Rule | KQL on Container App logs for `SUPPLIER_RATE_LIMIT_429` |

---

## Demo Scenario: Supplier Rate Limiting

The Grocery API simulates a rate-limited external supplier. When the supplier returns 429, the API returns 503 to clients.

**Trigger the scenario**:
```bash
cd demos/GrocerySreDemo
./scripts/03-smoke-and-trigger.sh
```

**Key signals to investigate**:
- Logs: `{app="grocery-api"} | json | errorCode="SUPPLIER_RATE_LIMIT_429"`
- Metrics: `sum(rate(grocery_supplier_rate_limit_hits_total[5m]))`

---

## Quick Reference Commands

```bash
# Get current MCP proxy endpoint
az containerapp show -g rg-grocery-sre-demo -n ca-mcp-amg-proxy \
  --query properties.configuration.ingress.fqdn -o tsv | xargs -I{} echo "https://{}/mcp"

# Check SRE Agent status
az resource show -g rg-grocery-sre-demo -n sre-agent-grocery-demo \
  --resource-type Microsoft.App/agents \
  --query "{runningState:properties.runningState, actionMode:properties.actionConfiguration.mode}" -o json

# Test MCP proxy connectivity
curl -sS -X POST "https://ca-mcp-amg-proxy.mangoplant-51da0571.swedencentral.azurecontainerapps.io/mcp" \
  -H 'content-type: application/json' \
  -H 'accept: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
```

---

## Configuration Files

| File | Purpose |
|------|---------|
| `demo-config.json` | Deployed resource names and URLs |
| `knowledge/loki-queries.md` | LogQL query reference for SRE Agent |
| `knowledge/amw-queries.md` | PromQL query reference for SRE Agent |
| `knowledge/grocery-environment.md` | This file — environment overview |
