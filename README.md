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

## 📁 Project Structure

```
.
├── .env                    # Environment configuration (not in git)
├── .env.example           # Template for environment variables
├── specs/
│   └── specs.md           # Complete lab specification
├── scripts/
│   ├── 10-clone-repos.sh  # Clone reference repositories
│   ├── 20-az-login.sh     # Azure authentication
│   ├── 30-deploy-octopets.sh        # Deploy infrastructure
│   ├── 31-deploy-octopets-containers.sh  # Build & deploy containers
│   ├── 40-deploy-sre-agent.sh       # Deploy SRE Agent
│   ├── load-env.sh        # Load environment variables
│   └── set-dotenv-value.sh          # Update .env values
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
