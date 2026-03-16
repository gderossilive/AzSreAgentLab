# Grubify Incident Lab Architecture

## Overview

This knowledge file describes the actual implementation of the Grubify incident lab in this repository.

- Deployment entry point: `demos/GrubifyIncidentLab/azure.yaml`
- Infrastructure: `demos/GrubifyIncidentLab/infrastructure/`
- Post-provision automation: `demos/GrubifyIncidentLab/scripts/post-provision.sh`
- Application source used by the lab: `demos/GrubifyIncidentLab/src/grubify`
- Upstream source repository: `https://github.com/dm-chelupati/grubify.git`

This lab does not deploy a generic Node.js container. It deploys the vendored Grubify application in this repo:

- Backend: ASP.NET Core Web API (`GrubifyApi`)
- Frontend: React frontend (`grubify-frontend`)
- Hosting: Azure Container Apps
- Agent platform: Azure SRE Agent with Azure Monitor incidents enabled

---

## Deployment Model

The lab is deployed with `azd up` from `demos/GrubifyIncidentLab`.

### Control Plane

`azure.yaml` provisions only infrastructure through Bicep:

- `infra.provider: bicep`
- `infra.path: infrastructure`
- `hooks.postprovision: bash ./scripts/post-provision.sh`

There is intentionally no `services:` block in the lab-level `azure.yaml`. Container images are built remotely with Azure Container Registry Tasks in the post-provision step, so the demo does not require a local Docker daemon.

### Azure Resource Topology

`infrastructure/main.bicep` is subscription-scoped and creates a dedicated resource group:

- Resource group name pattern: `rg-${environmentName}`

It then deploys `resources.bicep`, which creates these main resources using generated names based on `uniqueString(resourceGroup().id, environmentName)`:

| Resource | Azure type | Naming pattern | Purpose |
|----------|------------|----------------|---------|
| Resource group | `Microsoft.Resources/resourceGroups` | `rg-${environmentName}` | Isolates the demo |
| Log Analytics workspace | `Microsoft.OperationalInsights/workspaces` | `law-${uniqueSuffix}` | Stores Container Apps logs |
| Application Insights | `Microsoft.Insights/components` | `appi-${uniqueSuffix}` | Stores SRE Agent telemetry |
| User-assigned managed identity | `Microsoft.ManagedIdentity/userAssignedIdentities` | `id-sre-${uniqueSuffix}` | Agent action and knowledge graph identity |
| Container Apps environment | `Microsoft.App/managedEnvironments` | `cae-${uniqueSuffix}` | Shared environment for backend and frontend |
| Backend Container App | `Microsoft.App/containerApps` | `ca-grubify-${uniqueSuffix}` | Hosts the Grubify API |
| Frontend Container App | `Microsoft.App/containerApps` | `ca-grubify-fe-${uniqueSuffix}` | Hosts the React frontend |
| Azure Container Registry | `Microsoft.ContainerRegistry/registries` | `acr${containerAppName}` with hyphens removed | Remote image builds |
| SRE Agent | `Microsoft.App/agents` | `sre-agent-${uniqueSuffix}` | Incident detection and remediation |
| Action Group | `Microsoft.Insights/actionGroups` | `ag-sre-lab-${environmentName}` | Alert action target |
| Metric alert | `Microsoft.Insights/metricAlerts` | `alert-http-5xx-${environmentName}` | Triggers on backend HTTP 5xx |

---

## Container App Configuration

The deployment creates two Container Apps in the same Container Apps environment.

### Backend API Container App

Defined in `infrastructure/modules/container-app.bicep`:

- Name pattern: `ca-grubify-${uniqueSuffix}`
- External ingress: `true`
- Target port: `8080`
- CPU: `0.5`
- Memory: `1Gi`
- Scale: `minReplicas: 1`, `maxReplicas: 5`
- Initial image: placeholder hello-world image, later replaced by post-provision deployment

Runtime environment variables configured in Bicep:

- `ASPNETCORE_URLS=http://+:8080`
- `ASPNETCORE_ENVIRONMENT=Production`

After image deployment, the post-provision script also sets:

- `AllowedOrigins__0=<frontend-url>`

That matches the backend CORS policy in `src/grubify/GrubifyApi/Program.cs`.

### Frontend Container App

Also defined in `infrastructure/modules/container-app.bicep`:

- Name pattern: `ca-grubify-fe-${uniqueSuffix}`
- External ingress: `true`
- Target port: `80`
- CPU: `0.25`
- Memory: `0.5Gi`
- Scale: `minReplicas: 1`, `maxReplicas: 3`

Frontend runtime configuration is injected through:

- `REACT_APP_API_BASE_URL=https://<backend-fqdn>/api`

---

## Build And Release Flow

The lab uses `scripts/post-provision.sh` to turn the freshly provisioned infrastructure into a runnable demo.

### Image Build

The script runs remote builds in ACR:

- API image source: `src/grubify/GrubifyApi/Dockerfile`
- API image tag: `grubify-api:latest`
- Frontend image source: `src/grubify/grubify-frontend/Dockerfile`
- Frontend image tag: `grubify-frontend:latest`

### Deployment Updates

After the ACR builds finish, the script updates both Container Apps with `az containerapp update`.

This means the actual running demo is built from the vendored repository under `demos/GrubifyIncidentLab/src/grubify`, not from a prebuilt public image.

---

## Monitoring And Alerting

### Log Analytics

The Container Apps environment is configured with:

- `destination: log-analytics`
- Log Analytics workspace ID and shared key from the monitoring module

This is where the incident runbooks expect to query Container Apps logs.

### Application Insights

In this lab, Application Insights is created in `monitoring.bicep` and wired into the SRE Agent through `modules/sre-agent.bicep`:

- `properties.logConfiguration.applicationInsightsConfiguration.appId`
- `properties.logConfiguration.applicationInsightsConfiguration.connectionString`

This Application Insights instance is not the primary application telemetry path for the Grubify API in the current implementation. The API code does not configure the Application Insights SDK. The app investigation workflow relies mainly on:

- Azure Monitor resource metrics
- Container Apps platform logs in Log Analytics

### Alert Rule

The active alert configured by the lab is a single metric alert on the backend Container App:

- Metric namespace: `microsoft.app/containerapps`
- Metric name: `Requests`
- Dimension: `statusCodeCategory = 5xx`
- Threshold: `> 5`
- Aggregation: `Total`
- Window: `PT5M`
- Evaluation frequency: `PT1M`
- Severity: `3`

This alert is intentionally simple. The SRE Agent is expected to determine whether the 5xx symptom is caused by memory pressure, an OOM restart, a code bug, or another runtime issue.

---

## SRE Agent Configuration

The SRE Agent is defined in `infrastructure/modules/sre-agent.bicep` with:

- API version: `2025-05-01-preview`
- Name pattern: `sre-agent-${uniqueSuffix}`
- Identity type: `SystemAssigned, UserAssigned`
- Knowledge graph managed resource scope: the demo resource group
- Action mode: `autonomous`
- Access level: `Low`

The agent starts with an empty `mcpServers` list in ARM and is configured further by the post-provision script.

### Managed Identity Permissions

`modules/subscription-rbac.bicep` grants the user-assigned identity these subscription-scope roles:

- `Reader`
- `Monitoring Reader`
- `Monitoring Contributor`
- `Log Analytics Reader`
- `Container Apps Contributor`

This is the permission set the agent uses to inspect resources, query telemetry, and perform write actions such as Container App remediation.

### Incident Platform Wiring

`scripts/post-provision.sh` enables Azure Monitor as the incident platform by patching the agent resource with:

- `incidentManagementConfiguration.type = AzMonitor`

It then creates a response plan filter:

- Filter ID: `grubify-http-errors`
- Handling agent: `incident-handler`
- Mode: `autonomous`

So the runtime flow is:

1. Backend Container App emits HTTP 5xx.
2. Azure Monitor metric alert fires.
3. Azure Monitor incidents are enabled on the SRE Agent.
4. The `grubify-http-errors` response plan routes the incident to `incident-handler`.

---

## Knowledge Base And Subagents

The post-provision script uploads all Markdown files in `knowledge/` into Agent Memory. That includes:

- `http-500-errors.md`
- `incident-report-template.md`
- `grubify-architecture.md`
- `github-issue-triage.md` when GitHub integration is enabled

### Always-Created Subagent

The lab always creates `incident-handler`.

- Without GitHub PAT: `incident-handler-core.yaml`
- With GitHub PAT: `incident-handler-full.yaml`

Core tools used by `incident-handler`:

- `SearchMemory`
- `RunAzCliReadCommands`
- `RunAzCliWriteCommands`
- `GetAzCliHelp`
- `QueryLogAnalyticsByWorkspaceId`
- `QueryAppInsightsByResourceId`
- `ExecutePythonCode`

### Optional GitHub-Enabled Subagents

If `GITHUB_PAT` is present in the azd environment, the post-provision step also:

- Creates a GitHub MCP connector named `github-mcp`
- Creates `code-analyzer`
- Creates `issue-triager`
- Creates a scheduled task `triage-grubify-issues` with cron `0 */12 * * *`

The connector uses:

- Endpoint: `https://api.githubcopilot.com/mcp/`
- Auth type: bearer token from `GITHUB_PAT`

The default target repository is:

- `dm-chelupati/grubify`

If `GITHUB_USER` is set, the script instead targets:

- `${GITHUB_USER}/grubify`

---

## GitHub Repository Mapping

There are two repository contexts in this lab:

### 1. Local Source Used For Deployment

The app that Azure runs comes from the vendored copy at:

- `demos/GrubifyIncidentLab/src/grubify`

That working tree is cloned from:

- `https://github.com/dm-chelupati/grubify.git`

### 2. Remote Repository Used By GitHub MCP

When GitHub integration is enabled, the SRE Agent uses the GitHub MCP connector to inspect and update a GitHub repository. By default, that repository is also:

- `dm-chelupati/grubify`

That is why the YAML specs use `GITHUB_REPO_PLACEHOLDER` and the post-provision script resolves it before creating GitHub-aware subagents.

---

## Application Surface Actually Deployed

The backend routes are implemented by ASP.NET Core controllers under `src/grubify/GrubifyApi/Controllers/`.

Representative endpoints exposed by the deployed API include:

| Endpoint | Method | Implementation |
|----------|--------|----------------|
| `/weatherforecast` | `GET` | `WeatherForecastController` |
| `/api/restaurants` | `GET` | `RestaurantsController.GetRestaurants` |
| `/api/restaurants/{id}` | `GET` | `RestaurantsController.GetRestaurant` |
| `/api/restaurants/search?query=` | `GET` | `RestaurantsController.SearchRestaurants` |
| `/api/fooditems` | `GET` | `FoodItemsController.GetFoodItems` |
| `/api/fooditems/{id}` | `GET` | `FoodItemsController.GetFoodItem` |
| `/api/fooditems/restaurant/{restaurantId}` | `GET` | `FoodItemsController.GetFoodItemsByRestaurant` |
| `/api/orders` | `POST` | `OrdersController.PlaceOrder` |
| `/api/orders/{id}` | `GET` | `OrdersController.GetOrder` |
| `/api/orders/user/{userId}` | `GET` | `OrdersController.GetUserOrders` |
| `/api/cart/{userId}` | `GET` | `CartController.GetCart` |
| `/api/cart/{userId}/items` | `POST` | `CartController.AddItemToCart` |
| `/api/cart/{userId}/items/{itemId}` | `PUT` | `CartController.UpdateCartItem` |
| `/api/cart/{userId}` | `DELETE` | `CartController.ClearCart` |

Notes:

- There is no dedicated `/health` endpoint in the current API.
- There is no `/api/menu` route in the current API.
- The lab’s fault injection and investigation should focus on the routes above.

---

## Actual Failure Mode Used By The Demo

The intentional incident is implemented in `src/grubify/GrubifyApi/Controllers/CartController.cs`.

The `POST /api/cart/{userId}/items` handler does two things that matter for the incident:

1. It stores carts in a static in-memory dictionary: `UserCarts`.
2. It allocates a new `10 MB` byte array for every request and appends it to the static `RequestDataCache` list.

That second behavior is the direct memory leak in the current code:

- `var requestData = new byte[10 * 1024 * 1024];`
- `RequestDataCache.Add(requestData);`

Under repeated calls to `/api/cart/demo-user/items`, memory grows without cleanup until the container approaches its `1Gi` memory limit. The observed symptom becomes HTTP 5xx responses and potentially container restarts.

### Trigger Mechanism

`scripts/break-app.sh` repeatedly calls:

```bash
POST /api/cart/demo-user/items
```

with a JSON body like:

```json
{"foodItemId":1,"quantity":1}
```

The script defaults to:

- `200` requests
- `0.5` seconds between requests

---

## Troubleshooting Anchored To This Lab

### Primary Resources To Inspect

- Backend Container App: `ca-grubify-${uniqueSuffix}`
- Frontend Container App: `ca-grubify-fe-${uniqueSuffix}`
- Container Apps environment: `cae-${uniqueSuffix}`
- Log Analytics workspace: `law-${uniqueSuffix}`
- SRE Agent: `sre-agent-${uniqueSuffix}`
- Metric alert: `alert-http-5xx-${environmentName}`

### Metrics That Match The Runbook

The runbook in `knowledge/http-500-errors.md` is aligned to Azure Container Apps metrics such as:

- `UsageNanoCores`
- `WorkingSetBytes`
- `Requests`
- `RestartCount`
- `Replicas`
- `CpuPercentage`
- `MemoryPercentage`

### Useful Log Query Shape

For Container Apps console logs in the linked Log Analytics workspace:

```kql
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(1h)
| where Log_s contains "error" or Log_s contains "exception" or Log_s contains "500"
| summarize ErrorCount = count() by bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

---

## Summary

The Grubify incident lab in this repository is a Bicep + azd + Azure Container Apps deployment of a .NET API and React frontend, with an Azure SRE Agent configured to consume Azure Monitor incidents and optionally integrate with GitHub MCP against `dm-chelupati/grubify`.

The architecture is intentionally simple:

- one resource group per environment
- one backend Container App that fails under a real code-level memory leak
- one frontend Container App
- one Log Analytics workspace for app logs
- one Application Insights instance for agent telemetry
- one SRE Agent with autonomous incident handling
- one HTTP 5xx alert that routes incidents to the agent

That is the implementation agents should reason from when diagnosing Grubify incidents in this lab.
