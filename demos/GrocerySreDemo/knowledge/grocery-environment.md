# Grocery SRE Demo Environment (Sweden Central)

This environment hosts a small “Grocery” sample app running on Azure Container Apps, with centralized logging in Loki, dashboards in Managed Grafana, and an Azure SRE Agent attached for investigation/remediation.

## Deployed components

- **Container Apps Environment**: `cae-pu3vvmgkrke3q`
- **Grocery API (Container App)**: `ca-api-pu3vvmgkrke3q`
  - URL: https://ca-api-pu3vvmgkrke3q.mangoplant-51da0571.swedencentral.azurecontainerapps.io
- **Grocery Web (Container App)**: `ca-web-pu3vvmgkrke3q`
  - URL: https://ca-web-pu3vvmgkrke3q.mangoplant-51da0571.swedencentral.azurecontainerapps.io
- **Loki (Container App)**: `ca-loki`
  - URL: https://ca-loki.mangoplant-51da0571.swedencentral.azurecontainerapps.io
  - Used for LogQL investigations (see `loki-queries.md`).
- **Managed Grafana**: `amg-pu3vvmgkrke3q`
  - Endpoint: https://amg-pu3vvmgkrke3q-bnenf9hdb0erh5e4.cse.grafana.azure.com
- **Azure SRE Agent**: `sre-agent-grocery-demo`
  - Endpoint: https://sre-agent-grocery-demo--4e739d60.6d6a35f1.swedencentral.azuresre.ai

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

## Resource organization

- **Resource group**: `rg-grocery-sre-demo`
- **Container registry (ACR)**: `crpu3vvmgkrke3q`
- **Last known app image tag**: `20260129083730`

## Observability notes

- Logs are queryable in Loki. The primary app label used in queries is typically `app="grocery-api"`.
- Dashboards are published in Managed Grafana for service overview and drill-down.

## Alerts

- Scheduled Query Rule: **Grocery API - Supplier rate limit (SUPPLIER_RATE_LIMIT_429)** (created 2026-01-30)
