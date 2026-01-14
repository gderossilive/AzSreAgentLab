# Azure SRE Agent Lab Environment

A complete lab environment for testing Azure SRE Agent (Preview) with a realistic workload, deployed to Sweden Central region.

## 🎯 Overview

This lab deploys:
- **Octopets Sample Application**: A .NET Aspire application (React frontend + ASP.NET Core backend) running on Azure Container Apps
- **Azure SRE Agent**: AI-powered reliability assistant configured with High access scoped to the Octopets resource group only
- **Autonomous Health Monitoring**: Scheduled health checks with statistical anomaly detection and Teams notifications

### Included Demos

1. **ServiceNow Incident Automation** (`demos/ServiceNowAzureResourceHandler/`)
   - End-to-end automated incident response (Azure Monitor → ServiceNow → SRE Agent → GitHub)
   - See [ServiceNow Demo](#-servicenow-incident-automation-demo) for details

2. **Azure Health Check with Teams Alerts** (`demos/AzureHealthCheck/`)
   - Scheduled autonomous monitoring of Azure resources (Container Apps, VMs, AKS, App Service)
   - Statistical anomaly detection using MAD/z-score analysis
   - Cost monitoring, Azure Advisor integration, dependency health checks
   - Adaptive Card alerts sent to Microsoft Teams
   - See [Health Check Demo](#-azure-health-check-demo) for details

### Demo → scripts map

| Demo | Demo folder | Key config files | Related scripts (run order) |
|---|---|---|---|
| Azure Health Check (scheduled anomaly detection → Teams) | [demos/AzureHealthCheck/](demos/AzureHealthCheck/) | [demos/AzureHealthCheck/README.md](demos/AzureHealthCheck/README.md), [demos/AzureHealthCheck/azurehealthcheck-subagent-simple.yaml](demos/AzureHealthCheck/azurehealthcheck-subagent-simple.yaml) | [scripts/70-test-teams-webhook.sh](scripts/70-test-teams-webhook.sh) → [scripts/71-send-sample-anomaly.sh](scripts/71-send-sample-anomaly.sh) → (optional) [scripts/60-generate-traffic.sh](scripts/60-generate-traffic.sh) |
| ServiceNow Incident Automation (Azure Monitor alerts → ServiceNow incident → SRE Agent subagent) | [demos/ServiceNowAzureResourceHandler/](demos/ServiceNowAzureResourceHandler/) | [demos/ServiceNowAzureResourceHandler/README.md](demos/ServiceNowAzureResourceHandler/README.md), [demos/ServiceNowAzureResourceHandler/servicenow-subagent-simple.yaml](demos/ServiceNowAzureResourceHandler/servicenow-subagent-simple.yaml), [demos/ServiceNowAzureResourceHandler/servicenow-logic-app.bicep](demos/ServiceNowAzureResourceHandler/servicenow-logic-app.bicep), [demos/ServiceNowAzureResourceHandler/octopets-service-now-alerts.bicep](demos/ServiceNowAzureResourceHandler/octopets-service-now-alerts.bicep) | [scripts/50-deploy-logic-app.sh](scripts/50-deploy-logic-app.sh) → [scripts/50-deploy-alert-rules.sh](scripts/50-deploy-alert-rules.sh) → [scripts/63-enable-memory-errors.sh](scripts/63-enable-memory-errors.sh) (or [scripts/61-enable-cpu-stress.sh](scripts/61-enable-cpu-stress.sh)) → [scripts/60-generate-traffic.sh](scripts/60-generate-traffic.sh) → verify with [scripts/61-check-memory.sh](scripts/61-check-memory.sh) → cleanup: [scripts/64-disable-memory-errors.sh](scripts/64-disable-memory-errors.sh) / [scripts/62-disable-cpu-stress.sh](scripts/62-disable-cpu-stress.sh) |

## 📋 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Resource Group: rg-octopets-lab (Sweden Central)            │
├─────────────────────────────────────────────────────────────┤
│ • Container Apps Environment                                │
│ • Azure Container Registry                                  │
│ • Log Analytics Workspace                                   │
│ • Application Insights                                      │
│ • Backend Container App (ASP.NET Core)                      │
│ • Frontend Container App (React/Nginx)                      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Resource Group: rg-sre-agent-lab (Sweden Central)           │
├─────────────────────────────────────────────────────────────┤
│ • SRE Agent Resource                                        │
│ • Managed Identity (with scoped permissions)                │
│ • Log Analytics Workspace                                   │
│ • Application Insights                                      │
└─────────────────────────────────────────────────────────────┘
```

### RBAC Configuration

The SRE Agent's managed identity has **High access** with these roles scoped **only** to `rg-octopets-lab`:
- `Contributor` - Enables remediation actions
- `Reader` - Read access to resources
- `Log Analytics Contributor` - Access to logs for diagnostics

## 🚀 Quick Start

### Prerequisites

- Azure CLI (`az`)
- Bash shell
- Azure subscription with permissions to create resources and role assignments
- Dev container environment (included)

Notes:
- Local Docker is not required; container images are built remotely using Azure Container Registry (`az acr build`).

Permissions needed (common working combinations):
- Ability to run subscription-scope deployments that create resource groups (`az deployment sub create`)
- Ability to create RBAC role assignments scoped to the Octopets resource group and the SRE Agent resource group
- Typically: `Owner`, or `Contributor` + `User Access Administrator` at the required scopes

Region requirement:
- `swedencentral` (SRE Agent preview constraint)

Security constraints:
- Never commit `.env` (or any secrets)
- Do not grant the SRE Agent subscription-wide permissions; scope access to the target resource group(s) only

### Deployment

1. **Configure Environment**
   ```bash
   # Copy and edit .env with your Azure credentials
   cp .env.example .env
   ```

   Minimum variables for the happy path:
   - `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_LOCATION`
   - `OCTOPETS_ENV_NAME`
   - `SRE_AGENT_RG_NAME`, `SRE_AGENT_NAME`, `SRE_AGENT_ACCESS_LEVEL`

   Notes:
   - `OCTOPETS_RG_NAME` and `SRE_AGENT_TARGET_RESOURCE_GROUPS` are auto-populated by `scripts/30-deploy-octopets.sh`.
   - `OCTOPETS_API_URL` and `OCTOPETS_FE_URL` are auto-populated by `scripts/31-deploy-octopets-containers.sh`.

2. **Authenticate**
   ```bash
   source scripts/load-env.sh
   scripts/20-az-login.sh
   ```

3. **Deploy Octopets Infrastructure**
   ```bash
   scripts/30-deploy-octopets.sh
   ```

   This deploys infrastructure via Azure CLI + Bicep at subscription scope and sets `OCTOPETS_RG_NAME` in your `.env`.
   It also sets `SRE_AGENT_TARGET_RESOURCE_GROUPS` in your `.env` to the same RG name.

4. **Build and Deploy Containers**
   ```bash
   scripts/31-deploy-octopets-containers.sh
   ```

   This uses ACR remote builds (`az acr build`) and updates `.env` with `OCTOPETS_API_URL` and `OCTOPETS_FE_URL`.

   Verification:
   - Open the `OCTOPETS_FE_URL` in a browser; the frontend should load.

5. **Ensure SRE Agent reference repo is present**
   ```bash
   # Only needed if external/sre-agent is missing
   scripts/10-clone-repos.sh
   ```

6. **Deploy SRE Agent**
   ```bash
   scripts/40-deploy-sre-agent.sh
   ```

### Fresh environment (new deployment)

To create a fresh deployment (new resource groups), start with a fresh `.env` and new names:

```bash
rm -f .env
cp .env.example .env

# Edit these before deploying (examples)
scripts/set-dotenv-value.sh "OCTOPETS_ENV_NAME" "octopets-lab-$(date +%Y%m%d%H%M%S)"
scripts/set-dotenv-value.sh "SRE_AGENT_RG_NAME" "rg-sre-agent-lab-$(date +%Y%m%d%H%M%S)"
scripts/set-dotenv-value.sh "SRE_AGENT_NAME" "sre-agent-lab-$(date +%Y%m%d%H%M%S)"
```

Then follow the same happy-path deployment sequence above.

7. **[Optional] Deploy ServiceNow Integration Demo**
   ```bash
   # See demos/ServiceNowAzureResourceHandler/README.md for complete instructions
   # Requires ServiceNow developer instance and credentials in .env
   scripts/50-deploy-logic-app.sh
   scripts/50-deploy-alert-rules.sh
   ```

## 📁 Project Structure

```
.
├── .env                    # Environment configuration (not in git)
├── .env.example           # Template for environment variables
├── specs/
│   ├── specs.md           # Complete lab specification
│   └── IncidentAutomationServiceNow.md  # ServiceNow demo spec
├── scripts/
│   ├── 10-clone-repos.sh  # Bootstrap external repos (optional)
│   ├── 20-az-login.sh     # Azure authentication
│   ├── 30-deploy-octopets.sh        # Deploy Octopets infrastructure (Azure CLI + Bicep, subscription scope)
│   ├── 31-deploy-octopets-containers.sh  # Build & deploy containers (ACR remote builds, no Docker)
│   ├── 40-deploy-sre-agent.sh       # Deploy SRE Agent
│   ├── 50-deploy-alert-rules.sh     # Deploy ServiceNow integration
│   ├── load-env.sh        # Load environment variables
│   └── set-dotenv-value.sh          # Update .env values
├── demos/
│   ├── ServiceNowAzureResourceHandler/
│   │   ├── README.md      # ServiceNow demo execution guide
│   │   ├── servicenow-subagent-simple.yaml  # SRE Agent subagent
│   │   └── octopets-service-now-alerts.bicep       # Alert rules template
│   └── AzureHealthCheck/
│       ├── README.md      # Health check setup guide
│       └── azurehealthcheck-subagent-simple.yaml  # Health monitoring subagent
└── external/
    ├── octopets/          # Octopets sample app
    └── sre-agent/         # SRE Agent reference repo
```

## 🤖 Copilot prompts

Reusable prompt templates live under [.github/prompts/](.github/prompts/).

- Project setup: [.github/prompts/ProjectSetup.prompt.md](.github/prompts/ProjectSetup.prompt.md)
- Azure Health Check demo setup: [.github/prompts/AzureHealthCheckSetup.prompt.md](.github/prompts/AzureHealthCheckSetup.prompt.md)
- Trigger Octopets (Container Apps) anomaly: [.github/prompts/TriggerOctopetsAnomaly.prompt.md](.github/prompts/TriggerOctopetsAnomaly.prompt.md)
- ServiceNow demo setup: [.github/prompts/ServiceNowAzureResourceHandlerSetup.prompt.md](.github/prompts/ServiceNowAzureResourceHandlerSetup.prompt.md)
- ServiceNow demo run: [.github/prompts/ServiceNowDemoRun.prompt.md](.github/prompts/ServiceNowDemoRun.prompt.md)
- ServiceNow demo stop/cleanup: [.github/prompts/ServiceNowDemoStop.prompt.md](.github/prompts/ServiceNowDemoStop.prompt.md)
- Instance memory setup: [.github/prompts/MemorySetup.prompt.md](.github/prompts/MemorySetup.prompt.md)

### External repositories (vendored copies)

The directories under `external/` are **vendored snapshots** of upstream GitHub repositories.

- They are **not** Git submodules (no `.gitmodules`), and the vendored folders typically do **not** contain a `.git/` directory.
- Each vendored repo includes an `ORIGIN.md` documenting the upstream URL and why it was copied (and, for Octopets, what was modified).
- Updating a vendored repo is a manual process (re-vendor a pinned upstream ref and apply any lab-specific changes).

`scripts/10-clone-repos.sh` is provided as a convenience for fresh workspaces: it clones the upstream repos into `external/` only if the target directory does not already exist. In this repo, `external/` is already present and tracked in Git.

## 🔧 Configuration

### Environment Variables

Key variables in `.env`:

```bash
# Azure Context
AZURE_TENANT_ID=<your-tenant-id>
AZURE_SUBSCRIPTION_ID=<your-subscription-id>
AZURE_LOCATION=swedencentral

# Octopets Application
OCTOPETS_ENV_NAME=octopets-lab
OCTOPETS_RG_NAME=rg-octopets-lab

# SRE Agent
SRE_AGENT_RG_NAME=rg-sre-agent-lab
SRE_AGENT_NAME=sre-agent-lab
SRE_AGENT_ACCESS_LEVEL=High
SRE_AGENT_TARGET_RESOURCE_GROUPS=rg-octopets-lab

# ServiceNow Integration (Optional - for demo)
SERVICENOW_INSTANCE=dev12345
SERVICENOW_USERNAME=admin
SERVICENOW_PASSWORD=<password>
INCIDENT_NOTIFICATION_EMAIL=your-email@example.com
```

## 🛠️ Technical Details

### Deployment Approach

This lab uses a **Docker-free deployment** strategy:
- **Infrastructure**: Deployed via Bicep templates at subscription scope
- **Container Builds**: Remote builds using Azure Container Registry Tasks (`az acr build`)
- **Container Deployment**: Azure Container Apps

This approach bypasses the Docker Desktop requirement typically needed for .NET Aspire applications.

### Modified Dockerfiles

The original Octopets Dockerfiles were modified to work with the project root as the build context:
- `backend/Dockerfile`: Updated COPY paths for servicedefaults
- `frontend/Dockerfile`: Updated COPY paths for package.json and nginx.conf

## 📚 Reference Documentation

- **SRE Agent Repository**: https://github.com/microsoft/sre-agent
- **Octopets Sample**: https://github.com/Azure-Samples/octopets
- **SRE Agent Configuration**: https://github.com/microsoft/sre-agent/blob/main/samples/automation/configuration/00-configure-sre-agent.md
- **Bicep Deployment Guide**: https://github.com/microsoft/sre-agent/blob/main/samples/bicep-deployment/deployment-guide.md

## 🎭 ServiceNow Incident Automation Demo

The lab includes an optional demo that showcases automated incident management with ServiceNow:

**What it demonstrates:**
- Azure Monitor detects memory leak or CPU stress in Octopets backend
- ServiceNow incident automatically created via webhook
- SRE Agent investigates using Log Analytics and metrics
- GitHub issue created with root cause analysis
- ServiceNow incident updated with resolution details
- Microsoft Teams notifications sent to channels

**Quick Start:**
```bash
# 1. Sign up for ServiceNow developer instance (free)
# Visit: https://developer.servicenow.com/dev.do

# 2. Configure credentials in .env
scripts/set-dotenv-value.sh "SERVICENOW_INSTANCE" "dev12345"
scripts/set-dotenv-value.sh "SERVICENOW_USERNAME" "admin"
scripts/set-dotenv-value.sh "SERVICENOW_PASSWORD" "your-password"
scripts/set-dotenv-value.sh "INCIDENT_NOTIFICATION_EMAIL" "your-email@example.com"

# 3. Deploy Logic App webhook (writes SERVICENOW_WEBHOOK_URL into .env)
scripts/50-deploy-logic-app.sh

# 4. Deploy alert rules and action group
scripts/50-deploy-alert-rules.sh

# 4. Configure SRE Agent subagent (Azure Portal)
# Copy YAML from: demos/ServiceNowAzureResourceHandler/servicenow-subagent-simple.yaml

# 5. Run the demo
# See: demos/ServiceNowAzureResourceHandler/README.md for complete step-by-step instructions
```

**Components:**
- **4 Azure Monitor Alert Rules**: Memory (80%, 90%) and error rate (10, 50 per min) thresholds
- **Optional CPU alert**: Deploy separately via [scripts/65-deploy-cpu-alert.sh](scripts/65-deploy-cpu-alert.sh)
- **ServiceNow Action Group**: Webhook integration for incident creation
- **SRE Agent Subagent**: Automated investigation and remediation workflow with Teams notifications
- **Expected Duration**: 5-15 minutes end-to-end

**Documentation:**
- **Demo Guide**: [demos/ServiceNowAzureResourceHandler/README.md](demos/ServiceNowAzureResourceHandler/README.md)
- **Full Specification**: [specs/IncidentAutomationServiceNow.md](specs/IncidentAutomationServiceNow.md)
- **Subagent YAML**: [demos/ServiceNowAzureResourceHandler/servicenow-subagent-simple.yaml](demos/ServiceNowAzureResourceHandler/servicenow-subagent-simple.yaml)
- **Alert Rules**: [demos/ServiceNowAzureResourceHandler/octopets-service-now-alerts.bicep](demos/ServiceNowAzureResourceHandler/octopets-service-now-alerts.bicep)

### Testing Scenarios

The Octopets backend supports two independent stress testing scenarios:

**Memory Stress Testing** (allocates 1GB memory):
```bash
# Enable memory stress
./scripts/63-enable-memory-errors.sh

# Generate traffic to trigger allocation
./scripts/60-generate-traffic.sh 20

# Disable after testing
./scripts/64-disable-memory-errors.sh
```

**CPU Stress Testing** (burns CPU for 500ms per request):
```bash
# Enable CPU stress
./scripts/61-enable-cpu-stress.sh

# Generate traffic to trigger CPU burn
./scripts/60-generate-traffic.sh 50

# Disable after testing
./scripts/62-disable-cpu-stress.sh
```

**Combined Testing** (both scenarios simultaneously):
```bash
# Enable both flags
./scripts/63-enable-memory-errors.sh
./scripts/61-enable-cpu-stress.sh

# Generate traffic
./scripts/60-generate-traffic.sh 30

# Disable both
./scripts/64-disable-memory-errors.sh
./scripts/62-disable-cpu-stress.sh
```

These scenarios are useful for:
- Testing Azure Monitor alert rules
- Validating SRE Agent anomaly detection
- Demonstrating auto-remediation workflows
- Training on incident response

## 🏥 Azure Health Check Demo

The lab includes an autonomous health monitoring demo that uses statistical analysis to detect anomalies and send intelligent alerts to Microsoft Teams:

**What it demonstrates:**
- Scheduled health checks (daily, every 6h, every 12h) across multiple Azure resource types
- Statistical anomaly detection using Median Absolute Deviation (MAD) and z-score analysis
- Cost anomaly detection (>50% spike vs 7-day average)
- Azure Advisor recommendations integration (security, performance, cost, reliability)
- Resource dependency health monitoring
- Week-over-week trend analysis
- Auto-remediation suggestions based on detected anomalies
- Microsoft Teams notifications with rich Adaptive Cards

**Supported Resource Types:**
- Azure Container Apps
- Virtual Machines
- Azure Kubernetes Service (AKS)
- App Service (Web Apps, Function Apps)

**Detection Methods:**
- **Statistical Analysis**: MAD/z-score ≥3 for metrics over 24h window
- **Cost Monitoring**: Daily cost spikes >50% vs 7-day average
- **Azure Advisor**: High/Critical recommendations
- **Dependency Health**: Degraded/Unavailable linked resources
- **Week-over-Week**: 30% performance degradation vs same time last week

**Quick Start:**
```bash
# 1. Create Teams webhook via Power Automate
# Follow: demos/AzureHealthCheck/README.md (Power Automate Setup)

# 2. Configure webhook URL in .env
scripts/set-dotenv-value.sh "TEAMS_WEBHOOK_URL" "https://prod-xx.logic.azure.com:443/workflows/..."

# 3. Test webhook connectivity
scripts/70-test-teams-webhook.sh
scripts/71-send-sample-anomaly.sh

# 4. Upload subagent to Azure Portal
# Navigate to: Azure Portal → rg-sre-agent-lab → sre-agent-lab → Subagent Builder
# Upload: demos/AzureHealthCheck/azurehealthcheck-subagent-simple.yaml
# Trigger: Scheduled (cron: 0 0 * * * for daily at midnight)

# 5. Configure Teams connector in SRE Agent
# Navigate to: Connectors → Add Microsoft Teams
# Name: AzureHealthAlerts
# Webhook URL: (from .env TEAMS_WEBHOOK_URL)

# 6. Test manual execution
# Click "Run Now" in subagent → Monitor Execution History
```

**Teams Message Features:**
- Alert severity badges (Critical/High/Medium) with color coding
- Resource details (type, name, resource group, location, health status)
- Anomaly metrics with z-scores, baselines, min/max values, trend indicators (↑↓→)
- Week-over-week change percentages
- Top 3 Azure Advisor recommendations with categories
- Dependency health status for linked resources
- Analysis summary (root cause hypothesis, impact assessment, recommended actions)
- Auto-remediation options (scale-up/out, rightsizing, rollback suggestions)
- Action buttons (View in Portal, Metrics Dashboard, Logs, Cost Analysis, Advisor Recommendations)

**Adaptive Card Format:**
```json
{
  "type": "AdaptiveCard",
  "version": "1.4",
  "body": [
    {
      "type": "TextBlock",
      "text": "🔴 Critical Alert: Container App Memory Anomaly",
      "weight": "Bolder",
      "size": "Large",
      "color": "Attention"
    },
    {
      "type": "FactSet",
      "facts": [
        {"title": "Resource", "value": "octopetsapi"},
        {"title": "Z-Score", "value": "4.2"},
        {"title": "Current", "value": "1.2 GB"},
        {"title": "Baseline", "value": "512 MB"}
      ]
    }
  ]
}
```

**Monitoring Metrics:**
- **Container Apps**: Memory (WorkingSetBytes), CPU, Requests, Replicas
- **VMs**: CPU %, Available Memory, Disk I/O, Network I/O
- **AKS**: Node CPU/Memory %, Pod counts
- **App Service**: Memory, CPU, HTTP 5xx errors, Response time

**Scheduled Trigger Options:**
- Daily at midnight: `0 0 * * *`
- Every 6 hours: `0 */6 * * *`
- Every 12 hours: `0 */12 * * *`
- Business hours only (9 AM Mon-Fri): `0 9 * * 1-5`

**Documentation:**
- **Setup Guide**: [demos/AzureHealthCheck/README.md](demos/AzureHealthCheck/README.md)
- **Subagent YAML**: [demos/AzureHealthCheck/azurehealthcheck-subagent-simple.yaml](demos/AzureHealthCheck/azurehealthcheck-subagent-simple.yaml)
- **Test Scripts**: `scripts/70-test-teams-webhook.sh`, `scripts/71-send-sample-anomaly.sh`

**Configuration Variables:**
```bash
# Teams Integration
TEAMS_WEBHOOK_URL="https://prod-xx.logic.azure.com:443/workflows/..."  # Power Automate webhook
```

**Note**: Uses Power Automate "When a HTTP request is received" trigger, not traditional Teams Incoming Webhook.

## 🧪 Testing the Lab

### 1. Verify Octopets Application

Access the frontend at the URL from deployment output:
```bash
source scripts/load-env.sh
echo "Frontend: $OCTOPETS_FE_URL"
echo "Backend: $OCTOPETS_API_URL"
```

### 2. Configure SRE Agent

1. Navigate to Azure Portal → Resource Groups → `rg-sre-agent-lab` → `sre-agent-lab`
2. Configure Azure Monitor as the incident platform
3. Set up workflows and monitoring rules
4. Start in **Review** mode before switching to **Autonomous**

### 3. Create Test Alert

1. Create an Azure Monitor alert rule in `rg-octopets-lab`
2. Trigger the alert (e.g., CPU threshold)
3. Verify the SRE Agent ingests the incident
4. Confirm the agent can diagnose and suggest remediation with Contributor permissions

## 🔐 Security Considerations

- SRE Agent has **Contributor** access only to `rg-octopets-lab`, not the entire subscription
- Managed identity follows least-privilege principle
- All secrets are managed via Azure-native authentication (no keys in `.env`)

## 🧹 Cleanup

To delete all lab resources:

```bash
source scripts/load-env.sh

# Delete resource groups
az group delete -n rg-octopets-lab --yes --no-wait
az group delete -n rg-sre-agent-lab --yes --no-wait
```

## 📝 Notes

- **Region**: Sweden Central is one of 4 regions supporting Azure SRE Agent (eastus2, swedencentral, uksouth, australiaeast)
- **Access Model**: High access provides full remediation capabilities but is scoped to a single resource group
- **Incident Platform**: Azure Monitor integration requires additional configuration in the SRE Agent portal

## 🤝 Contributing

This is a lab environment. For issues or improvements:
1. Check the reference repositories for upstream updates
2. Review the [specs/specs.md](specs/specs.md) for design decisions
3. Test changes in a non-production subscription

## 📄 License

This lab environment references:
- Azure SRE Agent: See https://github.com/microsoft/sre-agent for license
- Octopets Sample: See https://github.com/Azure-Samples/octopets for license

---

**Last Updated**: December 2025  
**Lab Version**: 1.0  
**Supported Regions**: swedencentral (configured), eastus2, uksouth, australiaeast
