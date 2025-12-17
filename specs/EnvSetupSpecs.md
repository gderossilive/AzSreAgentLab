# Azure SRE Agent Lab — Hybrid Deployment Spec (Sweden Central)

## 1. Purpose
This lab provisions a realistic Azure workload using Azure Developer CLI (`azd`) and then deploys Azure SRE Agent (Preview) using the official reference repo’s Bicep templates, with permissions scoped to the workload’s resource group only.

This spec is written to be shareable:
- Uses placeholders for tenant/subscription IDs
- Avoids environment-specific secrets

## 2. Reference Repository
Use this repository as the authoritative reference for templates and samples:
- https://github.com/microsoft/sre-agent/tree/main

Notes:
- The SRE Agent resource deployment is provided via Bicep + scripts in the repo.
- `azd` is used in the repo’s documentation for deploying the sample workload (Octopets), not for deploying the SRE Agent resource.

## 3. Target Region
- Azure region: `swedencentral`

## 4. Design Decisions
### 4.1 Hybrid deployment (required)
- Workload (Octopets): deployed with `azd`
- Azure SRE Agent: deployed with Azure CLI + Bicep templates from the reference repo

### 4.2 Incident platform (required)
- Incident platform: Azure Monitor

### 4.3 Access model (required)
- Agent access level: `High`
- Scope restriction: grant `High` access only to the Octopets resource group (plus the agent’s own deployment resource group)

Rationale:
- `High` enables remediation actions (because it includes `Contributor`).
- Restricting the scope to the Octopets RG prevents unintended access to other environments.

## 5. Prerequisites
### 5.1 Tools
- Azure CLI (`az`)
- Azure Developer CLI (`azd`)
- Git
- Docker (required by Octopets sample)
- .NET SDK (required by Octopets sample)

### 5.2 Azure permissions
The deploying identity must be able to:
- Create resources in the agent deployment resource group
- Create role assignments (RBAC) at:
  - Agent deployment RG scope
  - Octopets RG scope

In practice, this often requires one of:
- `Owner` on the relevant scopes, or
- `Contributor` + `User Access Administrator` on the relevant scopes

### 5.3 Provider registration
Ensure required providers are registered (may already be registered in many tenants):
- `Microsoft.App` (required for the agent resource type)

## 6. Configuration Contract (.env)
All lab configuration values are organized in a single `.env` file at the workspace root.

### 6.1 `.env` keys (placeholders)
Create a `.env` file with at least:

```bash
# Azure context
AZURE_TENANT_ID=<AZURE_TENANT_ID>
AZURE_SUBSCRIPTION_ID=<AZURE_SUBSCRIPTION_ID>
AZURE_LOCATION=swedencentral

# Workload
OCTOPETS_ENV_NAME=octopets-lab
OCTOPETS_RG_NAME=<OCTOPETS_RESOURCE_GROUP_NAME>

# SRE Agent
SRE_AGENT_RG_NAME=rg-sre-agent-lab
SRE_AGENT_NAME=sre-agent-lab
SRE_AGENT_ACCESS_LEVEL=High

# Scope restriction: ONLY the Octopets RG
SRE_AGENT_TARGET_RESOURCE_GROUPS=<OCTOPETS_RESOURCE_GROUP_NAME>
# Optional (only needed for cross-subscription targeting)
SRE_AGENT_TARGET_SUBSCRIPTIONS=

# Optional: use an existing user-assigned managed identity; blank means create one
SRE_AGENT_EXISTING_MANAGED_IDENTITY_ID=
```

### 6.2 Mapping notes
- `AZURE_LOCATION` must be `swedencentral`.
- `SRE_AGENT_TARGET_RESOURCE_GROUPS` is a comma-separated list; in this lab it must contain exactly one value: the Octopets RG name.
- `SRE_AGENT_TARGET_SUBSCRIPTIONS` should be left blank unless you intentionally target resource groups in other subscriptions.

## 7. Deployment Flow
### 7.1 Login and set Azure context
```bash
az login --tenant <AZURE_TENANT_ID>
az account set --subscription <AZURE_SUBSCRIPTION_ID>

# (Optional) verify
az account show
```

### 7.2 Deploy Octopets workload with `azd`
Follow the Octopets setup guide referenced by the SRE Agent repo:
- https://github.com/microsoft/sre-agent/blob/main/samples/automation/sample-apps/octopets-setup.md

High-level intent:
1. Deploy Octopets into `swedencentral` using `azd`.
2. Capture the resource group name created by `azd`.
3. Set `OCTOPETS_RG_NAME` and `SRE_AGENT_TARGET_RESOURCE_GROUPS` to that RG name.

Example pattern (commands vary by Octopets repo instructions):
```bash
# In the Octopets repo directory
azd auth login --tenant <AZURE_TENANT_ID>
azd init
azd up

# Record the created RG name from azd output
```

### 7.3 Deploy Azure SRE Agent with Bicep (from reference repo)
Use the official Bicep deployment guide:
- https://github.com/microsoft/sre-agent/blob/main/samples/bicep-deployment/deployment-guide.md

Key requirements for this lab:
- `location = swedencentral`
- `accessLevel = High`
- `targetResourceGroups = ["<OCTOPETS_RESOURCE_GROUP_NAME>"]`

Recommended approach:
- Clone the reference repo into a subfolder (or use it as read-only reference)
- Run the provided deployment scripts under `samples/bicep-deployment/scripts/`

Example intent (exact script flags may evolve):
```bash
# In microsoft/sre-agent repo
cd samples/bicep-deployment/scripts

# Use the deploy script in non-interactive mode and pass only Octopets RG as the target
./deploy.sh --no-interactive \
  -s <AZURE_SUBSCRIPTION_ID> \
  -r <SRE_AGENT_RG_NAME> \
  -n <SRE_AGENT_NAME> \
  -l swedencentral \
  -a High \
  -t <OCTOPETS_RESOURCE_GROUP_NAME>
```

Expected outcome:
- SRE Agent resource created in `<SRE_AGENT_RG_NAME>`
- Managed identity created (unless `SRE_AGENT_EXISTING_MANAGED_IDENTITY_ID` is used)
- Role assignments applied:
  - In `<SRE_AGENT_RG_NAME>` (for agent’s own operation)
  - In `<OCTOPETS_RESOURCE_GROUP_NAME>` only (for scoped high access)

## 8. RBAC / Security Details
### 8.1 High access roles (target resource group)
Per the reference repo templates, `High` access assigns these built-in roles to the agent’s managed identity at the target RG scope:
- `Contributor`
- `Reader`
- `Log Analytics Reader`

Important:
- This is broad within the target RG (because `Contributor`).
- Restricting further (resource-level or custom role) requires modifying the Bicep templates.

### 8.2 Scope restriction requirement
This lab must only provide high access to:
- `<OCTOPETS_RESOURCE_GROUP_NAME>`

Do not add additional target resource groups.

## 9. Azure Monitor Incident Platform Setup
Use the SRE Agent configuration guide to connect/configure incident management:
- https://github.com/microsoft/sre-agent/blob/main/samples/automation/configuration/00-configure-sre-agent.md

Lab requirement:
- Choose/configure Azure Monitor as the incident source/platform.

Validation strategy:
1. Create (or reuse) an Azure Monitor alert rule in `<OCTOPETS_RESOURCE_GROUP_NAME>`.
2. Trigger the alert (controlled change or test condition).
3. Confirm an incident appears in the SRE Agent experience and the agent can triage/diagnose.

Note:
- Azure Monitor incident flows may be experimental depending on tenant/features; if alert→incident ingestion is inconsistent, validate the agent with a scheduled health-check subagent as a fallback.

## 10. Success Criteria
The lab is considered successful when:
- Octopets is deployed into `swedencentral` via `azd`.
- Azure SRE Agent is deployed into `swedencentral`.
- The agent’s managed identity has `Contributor` only on the Octopets RG (and not broadly across the subscription).
- An Azure Monitor alert from the Octopets RG is visible to the agent and the agent can perform incident triage.

## 11. Non-Goals
- Deploying Azure SRE Agent itself with `azd` (not provided in the reference repo).
- Subscription-wide permissions for the agent.
- Custom least-privilege role authoring (out of scope unless explicitly requested).
