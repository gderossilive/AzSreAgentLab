# AzSreAgentLab

Parent lab monorepo for Azure SRE Agent (Preview) demos.
Each demo lives in its own independent git repository under `demos/`.

## Demo Repositories

| Repo | Type | Description |
|---|---|---|
| [demos/octopets-lab/](demos/octopets-lab/) | Umbrella repo (3 submodules) | Octopets workload + health check + ServiceNow demos |
| [demos/ProactiveReliabilityAppService/](demos/ProactiveReliabilityAppService/) | Standalone | App Service slot-swap regression detection + autonomous rollback |
| [demos/GrocerySreDemo/](demos/GrocerySreDemo/) | Standalone | Grocery app on Container Apps + Managed Grafana + optional MCP |
| [demos/GrubifyIncidentLab/](demos/GrubifyIncidentLab/) | Standalone (`azd`) | Food-ordering app memory leak: 3-persona incident response |
| [demos/DomainControllerHealthAgent/](demos/DomainControllerHealthAgent/) | Standalone (YAML only) | Scheduled AD Domain Controller health monitoring via KQL |

## octopets-lab (Umbrella)

`demos/octopets-lab/` is an umbrella repo with three git submodules:

| Submodule | Description |
|---|---|
| `octopets/` | Octopets sample app (React + ASP.NET Core/.NET Aspire) |
| `AzureHealthCheck/` | Scheduled anomaly detection → Teams Adaptive Card alerts |
| `ServiceNowAzureResourceHandler/` | Azure Monitor alert → Logic App → ServiceNow incident → SRE Agent |

See [demos/octopets-lab/README.md](demos/octopets-lab/README.md) for deployment instructions.

## Demo Summaries

### Proactive Reliability (App Service Slot Swap)
Deploys an App Service with `production` + `staging` slots. Publishes a "bad" (slow) build to staging, swaps it into production, and expects the SRE Agent to detect the response-time regression via Application Insights and autonomously swap back.
→ [demos/ProactiveReliabilityAppService/README.md](demos/ProactiveReliabilityAppService/README.md)

### Grocery SRE Demo
Grocery API + web app on Azure Container Apps with Managed Grafana. Demonstrates SRE Agent diagnosing intermittent 503 errors caused by upstream supplier rate-limiting. Optionally extends with Loki log pipeline and Grafana MCP server.
→ [demos/GrocerySreDemo/README.md](demos/GrocerySreDemo/README.md)

### Grubify Incident Lab
`azd up` demo: deploys Grubify (Node.js food ordering app) with an intentional memory leak. Three acts — IT Operations (autonomous diagnosis + remediation), Developer (code analysis → GitHub issue), Workflow Automation (issue triage).
→ [demos/GrubifyIncidentLab/README.md](demos/GrubifyIncidentLab/README.md)

### Domain Controller Health Agent
Scheduled SRE Agent subagent that monitors Active Directory Domain Controller health by detecting week-over-week anomalies in NTLM/Kerberos authentication and DNS query rates via Log Analytics KQL. Posts Teams alert only when a meaningful deviation is detected.
→ [demos/DomainControllerHealthAgent/README.md](demos/DomainControllerHealthAgent/README.md)

## Repository Layout

```
demos/
├── octopets-lab/              # umbrella git repo
│   ├── octopets/              # submodule — Octopets app source
│   ├── AzureHealthCheck/      # submodule — health check demo
│   ├── ServiceNowAzureResourceHandler/  # submodule — ServiceNow demo
│   ├── scripts/               # shared Octopets deployment scripts
│   ├── docker/                # OTel-instrumented Octopets Docker builds
│   ├── docs/
│   ├── loadtests/
│   ├── specs/
│   └── tools/
├── ProactiveReliabilityAppService/  # standalone git repo
├── GrocerySreDemo/                  # standalone git repo
├── GrubifyIncidentLab/              # standalone git repo (azd)
└── DomainControllerHealthAgent/     # standalone git repo (YAML only)
external/
├── octopets/                  # vendored Octopets upstream (read-only reference)
├── grocery-sre-demo/          # vendored grocery upstream (read-only reference)
├── sre-agent/                 # vendored SRE Agent samples (read-only reference)
└── sre-agent-lab/             # vendored SRE Agent lab upstream (read-only reference)
```

> **Note**: `external/` is read-only vendored source. Demos build from
> their own copies (e.g., `octopets-lab/octopets/` submodule) or reference
> `external/` as a build context (e.g., `GrocerySreDemo` uses
> `external/grocery-sre-demo/src` for ACR container builds).

## Prerequisites (common)

- Azure CLI (`az`) authenticated — `az login`
- Azure subscription with permissions to create resource groups and RBAC assignments
- Region: `swedencentral` (SRE Agent preview constraint)
- No local Docker required — container images are built via `az acr build`

## Security Notes

- Never commit `.env` or any secrets — all demo repos include `.env` in `.gitignore`
- Do not grant the SRE Agent subscription-wide permissions — scope RBAC to the target resource group(s) only
