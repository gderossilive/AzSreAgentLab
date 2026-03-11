---
agent: agent
---

# GrubifyLabSetup

## Goal
Deploy the **Grubify Incident Lab** — a standalone azd-based demo that provisions a Grubify food ordering app + Azure SRE Agent with autonomous incident response.

## Steps

### 1) Prerequisites check

```bash
az account show --query '{subscription:name,id:id}' -o json
command -v azd && azd version
```

### 2) Clone Grubify source

```bash
cd /workspaces/AzSreAgentLab/demos/GrubifyIncidentLab
if [ ! -d src/grubify/GrubifyApi ]; then
  git clone https://github.com/dm-chelupati/grubify.git src/grubify
fi
ls src/grubify/
```

### 3) Create azd environment

```bash
cd /workspaces/AzSreAgentLab/demos/GrubifyIncidentLab
azd env new grubify-lab
```

### 4) (Optional) Enable GitHub integration

Only needed for Developer (Act 2) and Workflow (Act 3) personas:

```bash
azd env set GITHUB_PAT <your-github-pat>
azd env set GITHUB_USER <your-github-username>
```

### 5) Deploy

```bash
cd /workspaces/AzSreAgentLab/demos/GrubifyIncidentLab
azd up
```

This provisions infrastructure (Bicep), builds the Grubify container in ACR, uploads knowledge base files to the agent, creates subagents, and sets up the response plan.

### 6) Verify deployment

```bash
cd /workspaces/AzSreAgentLab/demos/GrubifyIncidentLab

# Check Container App is healthy
APP_URL=$(azd env get-value CONTAINER_APP_URL 2>/dev/null)
curl -s -o /dev/null -w "Health: HTTP %{http_code}\n" "${APP_URL}/health"

# Check SRE Agent details
RG=$(azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null)
AGENT=$(azd env get-value SRE_AGENT_NAME 2>/dev/null)
az resource show -g "$RG" -n "$AGENT" \
  --resource-type Microsoft.App/agents \
  --query '{name:name, mode:properties.actionConfiguration.mode, accessLevel:properties.actionConfiguration.accessLevel}' -o json
```

## Success Criteria
- `azd up` completes without errors
- Container App health check returns HTTP 200
- SRE Agent shows `mode: autonomous`
- Agent portal accessible at https://sre.azure.com

## Constraints
- Region must be `swedencentral`, `eastus2`, or `australiaeast`
- No secrets in committed files
- No local Docker required — ACR builds are cloud-side
