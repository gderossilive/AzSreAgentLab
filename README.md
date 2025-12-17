# Azure SRE Agent Lab Environment

A complete lab environment for testing Azure SRE Agent (Preview) with a realistic workload, deployed to Sweden Central region.

## 🎯 Overview

This lab deploys:
- **Octopets Sample Application**: A .NET Aspire application (React frontend + ASP.NET Core backend) running on Azure Container Apps
- **Azure SRE Agent**: AI-powered reliability assistant configured with High access scoped to the Octopets resource group only

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
- Azure subscription with permissions to create resources and role assignments
- Dev container environment (included)

### Deployment

1. **Configure Environment**
   ```bash
   # Copy and edit .env with your Azure credentials
   cp .env.example .env
   ```

2. **Authenticate**
   ```bash
   source scripts/load-env.sh
   scripts/20-az-login.sh
   ```

3. **Deploy Octopets Infrastructure**
   ```bash
   scripts/30-deploy-octopets.sh
   ```

4. **Build and Deploy Containers**
   ```bash
   scripts/31-deploy-octopets-containers.sh
   ```

5. **Deploy SRE Agent**
   ```bash
   scripts/40-deploy-sre-agent.sh
   ```

6. **[Optional] Deploy ServiceNow Integration Demo**
   ```bash
   # See demo/README.md for complete instructions
   # Requires ServiceNow developer instance and credentials in .env
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
│   ├── 10-clone-repos.sh  # Clone reference repositories
│   ├── 20-az-login.sh     # Azure authentication
│   ├── 30-deploy-octopets.sh        # Deploy infrastructure
│   ├── 31-deploy-octopets-containers.sh  # Build & deploy containers
│   ├── 32-configure-health-probes.sh     # Configure health probes
│   ├── 35-apply-memory-fix.sh       # Apply memory fix patch
│   ├── 40-deploy-sre-agent.sh       # Deploy SRE Agent
│   ├── 50-deploy-alert-rules.sh     # Deploy ServiceNow integration
│   ├── 60-generate-traffic.sh       # Generate test traffic
│   ├── 61-check-memory.sh           # Check memory usage
│   ├── load-env.sh        # Load environment variables
│   └── set-dotenv-value.sh          # Update .env values
├── demo/
│   ├── README.md          # ServiceNow demo execution guide
│   ├── QUICK_REFERENCE_MEMORY_FIX.md  # Quick deployment guide
│   ├── OCTOPETS_MEMORY_FIX.md         # Detailed fix documentation
│   ├── INCIDENT_RESPONSE_INC0010008.md  # Incident analysis
│   ├── octopets-memory-fix.patch      # Code changes patch
│   ├── servicenow-azure-resource-error-handler.yaml  # SRE Agent subagent
│   └── octopets-alert-rules.bicep   # Alert rules template
└── external/
    ├── octopets/          # Octopets sample app
    └── sre-agent/         # SRE Agent reference repo
```

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
- Azure Monitor detects memory leak in Octopets backend
- ServiceNow incident automatically created via webhook
- SRE Agent investigates using Log Analytics and metrics
- GitHub issue created with root cause analysis
- ServiceNow incident updated with resolution details
- Email notifications sent to stakeholders

**Quick Start:**
```bash
# 1. Sign up for ServiceNow developer instance (free)
# Visit: https://developer.servicenow.com/dev.do

# 2. Configure credentials in .env
scripts/set-dotenv-value.sh "SERVICENOW_INSTANCE" "dev12345"
scripts/set-dotenv-value.sh "SERVICENOW_USERNAME" "admin"
scripts/set-dotenv-value.sh "SERVICENOW_PASSWORD" "your-password"
scripts/set-dotenv-value.sh "INCIDENT_NOTIFICATION_EMAIL" "your-email@example.com"

# 3. Deploy alert rules and action group
scripts/50-deploy-alert-rules.sh

# 4. Configure SRE Agent subagent (Azure Portal)
# Copy YAML from: demo/servicenow-azure-resource-error-handler.yaml

# 5. Run the demo
# See: demo/README.md for complete step-by-step instructions
```

**Components:**
- **4 Azure Monitor Alert Rules**: Memory (80%, 90%) and error rate (10, 50 per min) thresholds
- **ServiceNow Action Group**: Webhook integration for incident creation
- **SRE Agent Subagent**: Automated investigation and remediation workflow
- **Expected Duration**: 5-15 minutes end-to-end

**Documentation:**
- **Demo Guide**: [demo/README.md](demo/README.md)
- **Full Specification**: [specs/IncidentAutomationServiceNow.md](specs/IncidentAutomationServiceNow.md)
- **Subagent YAML**: [demo/servicenow-azure-resource-error-handler.yaml](demo/servicenow-azure-resource-error-handler.yaml)
- **Alert Rules**: [demo/octopets-alert-rules.bicep](demo/octopets-alert-rules.bicep)

## 🧪 Testing the Lab

### 1. Apply Memory Fix (INC0010008)

**Important**: The Octopets sample contains deliberate test code that causes high memory usage. Apply the fix before deployment:

```bash
scripts/35-apply-memory-fix.sh
```

This removes test code that allocates 1GB of memory in production. See [demo/QUICK_REFERENCE_MEMORY_FIX.md](demo/QUICK_REFERENCE_MEMORY_FIX.md) for details.

**What it fixes:**
- Removes `AReallyExpensiveOperation()` that allocated 1GB memory
- Removes `ERRORS=true` flag from production mode
- Adds health endpoints: `/health/live`, `/health/ready`
- Increases memory limit: 1Gi → 2Gi
- Reduces concurrency: 10 → 5 requests per replica

**Expected results:**
- Memory usage: ~870 MiB → ~110-120 MiB (87% reduction)
- Memory percentage: 86% → 6-7% of limit

### 2. Verify Octopets Application

Access the frontend at the URL from deployment output:
```bash
source scripts/load-env.sh
echo "Frontend: $OCTOPETS_FE_URL"
echo "Backend: $OCTOPETS_API_URL"
```

### 2. Verify Octopets Application

Access the frontend at the URL from deployment output:
```bash
source scripts/load-env.sh
echo "Frontend: $OCTOPETS_FE_URL"
echo "Backend: $OCTOPETS_API_URL"
```

**Check memory usage:**
```bash
scripts/61-check-memory.sh
```

**Verify health endpoints:**
```bash
# Liveness probe
curl https://$(az containerapp show -n octopetsapi -g rg-octopets-lab --query "properties.configuration.ingress.fqdn" -o tsv)/health/live

# Readiness probe
curl https://$(az containerapp show -n octopetsapi -g rg-octopets-lab --query "properties.configuration.ingress.fqdn" -o tsv)/health/ready
```

### 3. Configure SRE Agent

1. Navigate to Azure Portal → Resource Groups → `rg-sre-agent-lab` → `sre-agent-lab`
2. Configure Azure Monitor as the incident platform
3. Set up workflows and monitoring rules
4. Start in **Review** mode before switching to **Autonomous**

### 4. Create Test Alert

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
