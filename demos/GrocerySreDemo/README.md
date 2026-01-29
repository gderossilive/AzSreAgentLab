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

## Optional: Loki + Grafana MCP

The upstream demo pushes structured logs to Loki and queries them via Grafana.

This lab scaffolds the core Azure resources and the app; Loki + MCP are intentionally not deployed by default.

- Upstream Loki query guidance: `knowledge/loki-queries.md`
- Token-based Grafana MCP module (may not work in Azure Managed Grafana if service account tokens are disabled): `external/grocery-sre-demo/infra/mcp-server.bicep`
- Managed-identity Azure Managed Grafana MCP Dockerfile: `external/grocery-sre-demo/infra/amg-mcp/Dockerfile`

### Deploy Loki (optional)

This deploys a `ca-loki` Container App and points the Grocery API at it via `LOKI_HOST`.

```bash
cd demos/GrocerySreDemo
./scripts/04-deploy-loki.sh
```

### Deploy Grafana MCP server (optional)

If your Azure Managed Grafana has service account tokens disabled, use the MI-based Azure Managed Grafana MCP.
This deploys a `ca-mcp-amg` Container App that exposes an SSE endpoint at `/sse`.

```bash
cd demos/GrocerySreDemo
./scripts/05-deploy-grafana-mcp.sh
```

## Files

- Infrastructure: `infrastructure/main.bicep`
- Generated config (no secrets): `demo-config.json`
- Scripts: `scripts/`

