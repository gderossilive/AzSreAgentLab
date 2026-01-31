# Grocery SRE Demo Environment (Sweden Central)

This environment hosts a small “Grocery” sample app running on Azure Container Apps, with centralized logging in Loki, dashboards in Managed Grafana, and an Azure SRE Agent attached for investigation/remediation.

## Deployed components

The concrete resource names and URLs can vary by deployment. Prefer using:

- `demos/GrocerySreDemo/demo-config.json` (app names + URLs)
- `az containerapp list/show` for current ingress FQDNs

## Optional: Grafana MCP (connectable from MCP clients)

The default lab script deploys an MI-based Grafana MCP as a **stdio MCP server** (not reachable over HTTP).
If you need an MCP endpoint that an MCP client can connect to over the network, deploy the HTTP/streamable variant:

```bash
cd demos/GrocerySreDemo
export GRAFANA_SERVICE_ACCOUNT_TOKEN="glsa_..."   # do not commit
./scripts/05-deploy-grafana-mcp-http.sh
```

This deploys `ca-mcp-grafana` and prints the endpoint:

- `https://<fqdn>/mcp` (transport: `streamable-http`)

## Optional: Grafana MCP (Managed Identity + connectable)

If service account tokens are disabled in Azure Managed Grafana, you can still get a connectable MCP endpoint by using managed identity:

```bash
cd demos/GrocerySreDemo
./scripts/05-deploy-grafana-mcp-amg-http.sh
```

This deploys `ca-mcp-amg-proxy` and prints:

- `https://<fqdn>/mcp` (transport: `streamable-http`)

To resolve the current MCP endpoint at any time:

```bash
fqdn=$(az containerapp show -g rg-grocery-sre-demo -n ca-mcp-amg-proxy --query properties.configuration.ingress.fqdn -o tsv)
echo "https://$fqdn/mcp"
```

This endpoint authenticates to Azure Managed Grafana using managed identity (Grafana Viewer/Editor RBAC on the Grafana resource).

### Notes for MCP clients / connector validators

The proxy is intentionally tolerant of “validator-style” traffic:

- `GET /mcp` without `mcp-session-id` returns `200` (SSE `: ok`) to avoid hard failures during validation.
- `DELETE /mcp` without `mcp-session-id` returns `200` (JSON `null`) for best-effort teardown.

For normal MCP usage, clients should use `POST /mcp` with JSON-RPC payloads (Streamable HTTP).

Minimal smoke test (JSON-only):

```bash
MCP_URL="https://<fqdn>/mcp"

curl -sS -i -X POST "$MCP_URL" \
  -H 'content-type: application/json' \
  -H 'accept: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
```

## Resource organization

- **Resource group**: `rg-grocery-sre-demo`
- **Container registry (ACR)**: `crpu3vvmgkrke3q`
- **Last known app image tag**: `20260129083730`

## Observability notes

- Logs are queryable in Loki. The primary app label used in queries is typically `app="grocery-api"`.
- Dashboards are published in Managed Grafana for service overview and drill-down.

## Alerts

- Scheduled Query Rule: **Grocery API - Supplier rate limit (SUPPLIER_RATE_LIMIT_429)** (created 2026-01-30)
