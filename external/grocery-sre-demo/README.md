# Grocery SRE Demo

A demo application showcasing an **AI SRE Agent** that can:
- Query logs from **Grafana/Loki** to investigate issues
- Create **Jira tickets** for incidents that need engineering attention

The grocery store app simulates **supplier API rate limiting** — a realistic SRE scenario where an external dependency starts failing.

## 🎯 What This Demo Shows

1. **Grocery API** experiences rate limiting from an external supplier API
2. **Loki** collects structured logs from the application
3. **Prometheus** scrapes metrics from the `/metrics` endpoint
4. **Azure Managed Grafana** visualizes logs and metrics
5. **MCP Servers** (Grafana + Jira) enable AI agents to query data and create tickets
6. **SRE Agent** uses context from the knowledge file to investigate and triage

## 🏗️ Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌──────────────────────┐
│   Web Frontend  │────▶│   Grocery API   │────▶│  Supplier API (sim)  │
│  (Container App)│     │  (Container App)│     │  (Rate Limited)      │
└─────────────────┘     └─────────────────┘     └──────────────────────┘
                               │
                    ┌──────────┴──────────┐
                    ▼                     ▼
             ┌───────────┐         ┌─────────────┐
             │   Loki    │         │ Prometheus  │
             │  (Logs)   │         │  (Metrics)  │
             └─────┬─────┘         └──────┬──────┘
                   │                      │
                   └──────────┬───────────┘
                              ▼
                    ┌─────────────────┐
                    │ Azure Managed   │
                    │    Grafana      │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
        ┌──────────┐  ┌──────────┐   ┌──────────┐
        │ MCP      │  │ MCP      │   │ Knowledge│
        │ Grafana  │  │ Jira     │   │ File     │
        └────┬─────┘  └────┬─────┘   └────┬─────┘
             │             │              │
             └─────────────┴──────────────┘
                           │
                    ┌──────┴──────┐
                    │  SRE Agent  │
                    │  (Copilot)  │
                    └─────────────┘
```

## 🚀 Quick Start

### Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Docker](https://docs.docker.com/get-docker/)
- Azure subscription

### Deploy the App

```bash
cd grocery-sre-demo

# Login to Azure
azd auth login

# Deploy everything (Container Apps, Grafana, etc.)
azd up
```

This deploys:
- Container Apps Environment
- Grocery API (Node.js)
- Web Frontend
- Azure Managed Grafana
- Container Registry

## 📊 Setting Up Loki & Prometheus

The `azd up` deploys the core infrastructure. For the full observability stack, deploy Loki as a Container App:

### Deploy Loki

```bash
# Get your resource group and environment
RG="rg-<your-env>"
CAE_NAME="cae-<your-token>"
ACR_NAME="cr<your-token>"

# Create Loki container app
az containerapp create \
  --name ca-loki \
  --resource-group $RG \
  --environment $CAE_NAME \
  --image grafana/loki:2.9.0 \
  --target-port 3100 \
  --ingress external \
  --min-replicas 1 \
  --cpu 0.5 \
  --memory 1Gi \
  --args "-config.file=/etc/loki/local-config.yaml"
```

### Configure Grafana Data Source

1. Go to Azure Managed Grafana → **Configuration** → **Data Sources**
2. Add **Loki** data source:
   - URL: `https://ca-loki.<your-env>.azurecontainerapps.io`
3. Add **Prometheus** data source (if using Azure Monitor):
   - Use Azure Monitor Workspace integration

### Update API to Push Logs to Loki

Set the `LOKI_HOST` environment variable on your API container:

```bash
az containerapp update \
  --name ca-api-<token> \
  --resource-group $RG \
  --set-env-vars "LOKI_HOST=https://ca-loki.<env>.azurecontainerapps.io"
```

## 🔌 Setting Up MCP Servers

MCP (Model Context Protocol) servers enable AI agents to interact with external tools.

### Grafana MCP Server

Deploy the Grafana MCP server as a Container App:

```bash
# Create a service account in Grafana first
# Go to Grafana → Administration → Service Accounts → Create
# Save the token

# Deploy MCP Grafana
az containerapp create \
  --name ca-mcp-grafana \
  --resource-group $RG \
  --environment $CAE_NAME \
  --image ghcr.io/grafana/mcp-grafana:latest \
  --target-port 8000 \
  --ingress external \
  --min-replicas 1 \
  --cpu 0.25 \
  --memory 0.5Gi \
  --env-vars \
    "GRAFANA_URL=https://amg-<token>.grafana.azure.com" \
    "GRAFANA_SERVICE_ACCOUNT_TOKEN=glsa_XXXXX" \
  --args '"-transport" "streamable-http" "-address" "0.0.0.0:8000"'
```

The MCP endpoint will be available at:
```
https://ca-mcp-grafana.<env>.azurecontainerapps.io/mcp
```

### Jira MCP Server

Deploy the Jira MCP server:

```bash
# Get your Jira API token from: https://id.atlassian.com/manage/api-tokens

az containerapp create \
  --name ca-mcp-jira \
  --resource-group $RG \
  --environment $CAE_NAME \
  --image ghcr.io/sooperset/mcp-atlassian:latest \
  --target-port 8000 \
  --ingress external \
  --min-replicas 1 \
  --cpu 0.25 \
  --memory 0.5Gi \
  --env-vars \
    "JIRA_URL=https://your-org.atlassian.net" \
    "JIRA_USERNAME=your-email@example.com" \
    "JIRA_API_TOKEN=ATATT3xXXXXX" \
    "TRANSPORT=streamable-http" \
    "HOST=0.0.0.0" \
    "PORT=8000"
```

The MCP endpoint will be available at:
```
https://ca-mcp-jira.<env>.azurecontainerapps.io/mcp
```

## 📚 Knowledge File for SRE Agent

The `knowledge/` folder contains context for the SRE agent:

- **`loki-queries.md`** - Ready-to-run Loki queries for investigating issues

This file provides:
- App registry with correct label values
- Query patterns for errors, rate limits, trends
- Common JSON fields in logs
- Issue pattern recognition guidance

The agent can read this file to quickly run the right queries without having to discover labels.

## 🧪 Triggering the Demo Scenario

### Option 1: Web UI
1. Open the web app URL
2. Click **"Trigger Rate Limit (Demo)"**
3. Observe errors in the response

### Option 2: API
```bash
# Trigger rate limit scenario
curl -X POST https://ca-api-<token>.azurecontainerapps.io/api/demo/trigger-rate-limit

# Check supplier status
curl https://ca-api-<token>.azurecontainerapps.io/api/supplier/status
```

### What Happens
1. API makes 15 rapid requests to simulated supplier
2. After 5 requests (configurable), supplier returns 429
3. Errors are logged to Loki with `errorCode: SUPPLIER_RATE_LIMIT_429`
4. Metrics are updated on `/metrics` endpoint

## 🤖 Using the SRE Agent

Once MCP servers are configured, ask the agent:

> "There are reports of inventory check failures. Can you investigate the logs and create a ticket if there's an issue?"

The agent will:
1. Read the knowledge file for query patterns
2. Query Loki via Grafana MCP for errors
3. Identify the rate limit pattern
4. Create a Jira ticket with findings

## 📁 Project Structure

```
grocery-sre-demo/
├── azure.yaml                 # Azure Developer CLI config
├── README.md                  # This file
├── infra/
│   ├── main.bicep             # Main infrastructure
│   ├── main.parameters.json
│   ├── resources.bicep        # Container Apps, Grafana
│   └── abbreviations.json
├── knowledge/
│   └── loki-queries.md        # SRE agent context
└── src/
    ├── api/                   # Backend API (Node.js)
    │   ├── index.js           # Main app with logging & metrics
    │   ├── package.json
    │   └── Dockerfile
    └── web/                   # Frontend
        ├── server.js
        ├── package.json
        └── Dockerfile
```

## 🔧 Configuration

### Environment Variables (API)

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | 3100 | API server port |
| `SUPPLIER_RATE_LIMIT` | 5 | Requests before rate limit |
| `RATE_LIMIT_RESET_MS` | 60000 | Rate limit reset window |
| `LOKI_HOST` | - | Loki push endpoint URL |

### Log Labels

Logs are pushed to Loki with these labels:

| Label | Value |
|-------|-------|
| `app` | `grocery-api` |
| `job` | `grocery-api` |
| `level` | `info`, `warn`, `error` |
| `environment` | `production` |

## 🔍 Useful Commands

```bash
# View container app logs
az containerapp logs show --name ca-api-<token> --resource-group $RG --follow

# Test MCP endpoint
curl -X POST https://ca-mcp-grafana.<env>.azurecontainerapps.io/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'

# Query Loki directly
curl -G "https://ca-loki.<env>.azurecontainerapps.io/loki/api/v1/query_range" \
  --data-urlencode 'query={app="grocery-api", level="error"}'
```

## 📝 License

MIT
