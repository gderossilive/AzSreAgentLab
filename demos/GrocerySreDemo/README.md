# Grocery SRE Demo (Container Apps + Grafana + SRE Agent)

This demo is based on the reference app in `external/grocery-sre-demo`, adapted to this lab’s conventions:

- Deploys infrastructure with Bicep (no `azd` required)
- Builds container images with ACR remote build (`az acr build`) (no local Docker required)
- Creates a dedicated Azure SRE Agent (`Microsoft.App/agents`) scoped to this demo resource group

## What gets deployed

The setup script deploys:

- Resource group (new)
- Log Analytics workspace
- Azure Container Apps environment
- Azure Container Registry
- Azure Managed Grafana
- Container Apps placeholders for `api` and `web`
- Azure SRE Agent (dedicated to this scenario)

Then you build and deploy the real `api`/`web` images from `external/grocery-sre-demo/src`.

## Prerequisites

- Azure CLI (`az`) logged in
- Subscription access to create a resource group + deploy Container Apps, ACR, Managed Grafana, and SRE Agent

## Deploy

From repo root:

1) Deploy infra + SRE Agent and write `demo-config.json`:

```bash
cd demos/GrocerySreDemo
./scripts/01-setup-demo.sh \
  --subscription-id 06dbbc7b-2363-4dd4-9803-95d07f1a8d3e \
  --location swedencentral \
  --resource-group rg-grocery-sre-demo \
  --environment-name grocery-sre-demo \
  --sre-agent-name sre-agent-grocery-demo
```

2) Build and deploy the app containers (ACR remote builds):

```bash
cd demos/GrocerySreDemo
./scripts/02-build-and-deploy-containers.sh
```

3) Smoke test + trigger the rate limit scenario:

```bash
cd demos/GrocerySreDemo
./scripts/03-smoke-and-trigger.sh
```

## Storyboard (assume setup + trigger are done)

Use this section as the presenter script. It assumes the environment is already deployed and the rate-limit scenario has already been triggered (intermittent `503` on inventory lookups).

### Scene 1 — Context

- “We have a grocery app running on Azure Container Apps (API + Web).”
- “Users intermittently fail to fetch inventory for products; the rest of the site may still look healthy.”

### Scene 2 — Define the symptom and blast radius

- Symptom anchor: inventory path intermittently returns `503`.
- Confirm it’s scoped: product listing and basic health checks still succeed.

### Scene 3 — Ask the SRE Agent to diagnose

- Open the SRE Agent experience for this demo resource group.
- Prompt idea: “Why are inventory requests intermittently failing with 503? Identify the failing dependency and evidence.”
- Expected output: correlation to supplier rate limiting / downstream dependency behavior; pointers to the most relevant signals.

### Scene 4 — Validate with Grafana

- Use Managed Grafana to confirm the story:
  - Inventory failures spike (supplier throttling -> `503` on inventory)
  - Failure % increases during the trigger window
  - Downstream rate-limit indicators: `SUPPLIER_RATE_LIMIT_429` + `retryAfter`

Optional: create an Azure Monitor alert to “intercept” supplier rate limiting (logs-based).
This watches the Grocery API Container App logs in Log Analytics for `SUPPLIER_RATE_LIMIT_429`.

```bash
cd demos/GrocerySreDemo

# Option A: create a new Action Group with an email receiver
./scripts/06-deploy-supplier-429-alert.sh --email you@example.com

# Option B: reuse an existing Action Group
./scripts/06-deploy-supplier-429-alert.sh --action-group-id "/subscriptions/<sub>/resourceGroups/<rg>/providers/microsoft.insights/actionGroups/<name>"
```

Tip: if Loki is deployed, create the Scene 4 custom dashboard and use it as your “single pane of glass”:

```bash
cd demos/GrocerySreDemo
./scripts/07-create-custom-grafana-dashboard.sh --dashboard scene4
```

### Scene 5 (optional) — Deep log forensics with Loki

- If Loki is deployed and the API is configured to push logs, use `knowledge/loki-queries.md` to:
  - isolate inventory requests
  - spot rate-limit responses/errors
  - correlate by time window and request patterns

### Scene 6 — Remediation options (pick 1–2)

- Reliability patterns to discuss:
  - retry with jitter + timeout on supplier calls
  - circuit breaker / bulkhead isolation
  - short-TTL caching for inventory lookups
  - graceful degradation / fallback behavior

### Scene 7 — Close

- “After mitigation, the inventory path is resilient under supplier throttling, and we have clear observability + an agent narrative for faster triage next time.”

## Check status (Azure)

Use these commands to confirm the demo is up and running:

```bash
rg=rg-grocery-sre-demo

# Resource group
az group show -n "$rg" --query '{name:name, location:location, provisioningState:properties.provisioningState}' -o json

# Container Apps
az containerapp list -g "$rg" --query "[].{name:name, provisioningState:properties.provisioningState, runningStatus:properties.runningStatus, fqdn:properties.configuration.ingress.fqdn}" -o table

# SRE Agent
az resource show -g "$rg" -n sre-agent-grocery-demo --resource-type Microsoft.App/agents \
  --query '{name:name, endpoint:properties.agentEndpoint, actionMode:properties.actionConfiguration.mode, powerState:properties.powerState, runningState:properties.runningState}' -o json

# Managed Grafana
az grafana list -g "$rg" --query "[].{name:name, provisioningState:properties.provisioningState, endpoint:properties.endpoint}" -o table
```

Note: right after creation, the SRE Agent may show `runningState=BuildingKnowledgeGraph` for a while.

## Optional: Loki + Grafana MCP

The upstream demo pushes structured logs to Loki and queries them via Grafana.

This lab scaffolds the core Azure resources and the app; Loki + MCP are not deployed by default.
If you previously ran the scripts below, you may already have `ca-loki` and `ca-mcp-amg` deployed.

- Upstream Loki query guidance: `knowledge/loki-queries.md`
- Token-based Grafana MCP module (may not work in Azure Managed Grafana if service account tokens are disabled): `external/grocery-sre-demo/infra/mcp-server.bicep`
- Managed-identity Azure Managed Grafana MCP Dockerfile: `external/grocery-sre-demo/infra/amg-mcp/Dockerfile`

### Deploy Loki (optional)

This deploys a `ca-loki` Container App and points the Grocery API at it via `LOKI_HOST`.

```bash
cd demos/GrocerySreDemo
./scripts/04-deploy-loki.sh
```

### Create a custom dashboard in Azure Managed Grafana (optional)

This creates a Loki datasource in your Managed Grafana instance (pointing at `ca-loki`) and then creates/updates a custom dashboard:

```bash
cd demos/GrocerySreDemo
./scripts/07-create-custom-grafana-dashboard.sh

# Or: create the storyboard Scene 4 dashboard (inventory failure validation)
./scripts/07-create-custom-grafana-dashboard.sh --dashboard scene4
```

If Loki is not deployed yet, run `./scripts/04-deploy-loki.sh` first.

### Deploy Grafana MCP server (optional)

If your Azure Managed Grafana has service account tokens disabled, use the MI-based Azure Managed Grafana MCP.
This deploys a `ca-mcp-amg` Container App as a **stdio MCP server** (no HTTP/SSE ingress).

If you see a `ca-mcp-amg-debug` app, it is a troubleshooting variant used during iteration.

```bash
cd demos/GrocerySreDemo
./scripts/05-deploy-grafana-mcp.sh
```

### Deploy Grafana MCP server (Managed Identity + HTTP, connectable from MCP clients)

If you need both:

- **Managed Identity auth** to Azure Managed Grafana (no service account token)
- A **network-reachable** MCP endpoint for an external MCP client

Deploy the MI-based HTTP proxy MCP server:

```bash
cd demos/GrocerySreDemo
./scripts/05-deploy-grafana-mcp-amg-http.sh
```

This deploys `ca-mcp-amg-proxy` and prints the MCP endpoint:

- `https://<fqdn>/mcp`
- Transport: `streamable-http`

Current lab endpoint:

- https://ca-mcp-amg-proxy.mangoplant-51da0571.swedencentral.azurecontainerapps.io/mcp
- Health: https://ca-mcp-amg-proxy.mangoplant-51da0571.swedencentral.azurecontainerapps.io/healthz

#### Azure SRE Agent connector settings (portal)

- **Connection type**: Streamable HTTP
- **URL**: use the full `/mcp` URL above
- **Auth**: none at the connector (Grafana auth is done server-side via managed identity)

If the portal validator probes `GET /mcp` or `DELETE /mcp` without a session id, the proxy returns `200` to avoid hard failures.

### Deploy Grafana MCP server (HTTP/streamable, connectable from MCP clients)

If you need an MCP endpoint that an MCP client can connect to over the network, deploy the **HTTP/streamable** MCP server.

Prereq: create a Grafana **service account token** in Azure Managed Grafana.

```bash
cd demos/GrocerySreDemo

# Do not commit this token. Prefer setting it only in your current shell.
export GRAFANA_SERVICE_ACCOUNT_TOKEN="glsa_..."

./scripts/05-deploy-grafana-mcp-http.sh
```

This deploys `ca-mcp-grafana` with external ingress and prints the MCP endpoint:

- `https://<fqdn>/mcp`
- Transport: `streamable-http`

## Files

- Infrastructure: `infrastructure/main.bicep`
- Generated config (no secrets): `demo-config.json`
- Scripts: `scripts/`

