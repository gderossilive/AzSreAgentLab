# GitHub Copilot Instructions - Azure SRE Agent Lab

## Project Context

This is an Azure SRE Agent lab environment that deploys a sample application (Octopets) and configures Azure SRE Agent with scoped permissions. The lab runs entirely in a dev container without Docker Desktop.

**Included Demos**:
1. **ServiceNow Incident Automation** (`demos/ServiceNowAzureResourceHandler/`): End-to-end automated incident response (Azure Monitor → ServiceNow → SRE Agent → GitHub → Email)
2. **Azure Health Check** (`demos/AzureHealthCheck/`): Scheduled autonomous monitoring with statistical anomaly detection, cost tracking, Azure Advisor integration, and Microsoft Teams notifications via Adaptive Cards

## Key Technologies

- **Azure Services**: Container Apps, Container Registry, SRE Agent (Preview), Log Analytics, Application Insights
- **Languages**: Bash (scripts), Bicep (IaC), TypeScript/React (frontend), C#/.NET 9 (backend)
- **Tools**: Azure CLI, Azure Developer CLI (azd), .NET SDK 9, Node.js 20
- **Region**: Sweden Central (swedencentral)

## Architecture Patterns

### Deployment Strategy
- **Infrastructure**: Bicep templates deployed at subscription scope
- **Container Builds**: Remote builds via Azure Container Registry Tasks (no local Docker)
- **RBAC**: Managed identity with High access scoped to single resource group only

### File Organization
```
scripts/        # Deployment automation (bash)
specs/          # Lab specifications (markdown)
demos/          # Demo use cases
  ServiceNowAzureResourceHandler/  # ServiceNow incident automation
  AzureHealthCheck/                # Scheduled health monitoring with Teams
external/       # Cloned reference repositories
.env            # Environment configuration (gitignored)
.env.example    # Template for .env
```

## Coding Guidelines

### Bash Scripts
- Use `set -euo pipefail` for safety
- Validate required environment variables with `${VAR:?Missing VAR}`
- Include usage comments at script header
- Use absolute paths when working across directories
- Echo status messages for user visibility

Example:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Deploy infrastructure
: "${AZURE_SUBSCRIPTION_ID:?Missing AZURE_SUBSCRIPTION_ID}"
echo "Deploying to subscription: $AZURE_SUBSCRIPTION_ID"
```

### Bicep Templates
- Use subscription scope for deployments that create resource groups
- Parameterize location, environment name, and tags
- Include descriptive comments for complex resources
- Follow Azure naming conventions (e.g., `rg-`, `cae-`, `law-`)

### Docker Considerations
- **Build context**: Always use project root, not subdirectories
- **COPY paths**: Reference subdirectories explicitly (e.g., `COPY backend/ ./backend`)
- **ACR builds**: Use `az acr build` with `-f` for Dockerfile path and `.` for root context

Example:
```bash
cd /workspaces/AzSreAgentLab/external/octopets
az acr build -r $ACR_NAME -t $IMAGE_TAG -f backend/Dockerfile .
```

## Environment Variables

### Required Variables
Always validate these exist before deployment:
- `AZURE_TENANT_ID` - Azure AD tenant
- `AZURE_SUBSCRIPTION_ID` - Target subscription
- `AZURE_LOCATION` - Deployment region (swedencentral)
- `OCTOPETS_ENV_NAME` - Environment name for resource naming

### Auto-populated Variables
These are set by deployment scripts:
- `OCTOPETS_RG_NAME` - Resource group created by deployment
- `OCTOPETS_API_URL` - Backend container app URL
- `OCTOPETS_FE_URL` - Frontend container app URL
- `SRE_AGENT_TARGET_RESOURCE_GROUPS` - Scoped access for agent
- `SERVICENOW_WEBHOOK_URL` - Auto-populated after alert deployment

### ServiceNow Demo Variables (Optional)
Required only for incident automation demo:
- `SERVICENOW_INSTANCE` - ServiceNow instance prefix (e.g., dev12345)
- `SERVICENOW_USERNAME` - ServiceNow admin username
- `SERVICENOW_PASSWORD` - ServiceNow admin password
- `INCIDENT_NOTIFICATION_EMAIL` - Email for notifications

### AzureHealthCheck Demo Variables (Optional)
Required only for health monitoring demo:
- `TEAMS_WEBHOOK_URL` - Power Automate workflow webhook URL (quoted, contains & characters)

## Common Patterns

### Loading Environment
```bash
source scripts/load-env.sh
```

### Updating .env Values
```bash
scripts/set-dotenv-value.sh "KEY_NAME" "value"
```

### Azure CLI Authentication
```bash
az account show >/dev/null 2>&1 || {
  echo "ERROR: Not logged in. Run scripts/20-az-login.sh" >&2
  exit 1
}
```

### ACR Remote Build
```bash
cd /path/to/project/root
az acr build -r $ACR_NAME -t $IMAGE:$TAG -f path/to/Dockerfile .
```

### ServiceNow Demo Deployment
```bash
# Deploy alert rules with ServiceNow integration
scripts/50-deploy-alert-rules.sh

# Trigger demo memory leak
az containerapp update -n octopetsapi -g rg-octopets-lab --set-env-vars "MEMORY_ERRORS=true"

# Disable after testing
az containerapp update -n octopetsapi -g rg-octopets-lab --set-env-vars "MEMORY_ERRORS=false"
```

### AzureHealthCheck Demo Testing
```bash
# Test Teams webhook connectivity
scripts/70-test-teams-webhook.sh

# Send sample anomaly alert
scripts/71-send-sample-anomaly.sh

# Upload subagent to Azure Portal
# File: demos/AzureHealthCheck/azurehealthcheck-subagent-simple.yaml
# Trigger: Scheduled (cron: 0 */6 * * * for every 6 hours)

# Configure Teams connector in SRE Agent portal
# Connectors → Add Microsoft Teams → Use TEAMS_WEBHOOK_URL from .env
```

## Security Best Practices

### RBAC Scoping
- Never grant subscription-wide permissions to SRE Agent
- Always scope to specific resource groups via `SRE_AGENT_TARGET_RESOURCE_GROUPS`
- Use managed identities, not service principals with keys

### Secrets Management
- Never commit `.env` file (in .gitignore)
- Use Azure CLI/azd authentication, not hardcoded credentials
- Store sensitive values only in Azure Key Vault or managed identities

## Troubleshooting Hints

### Common Issues
1. **"Please run 'az login'"** → Authentication expired, run `scripts/20-az-login.sh`
2. **"Docker daemon not running"** → Use ACR Tasks instead: `az acr build`
3. **"COPY failed: forbidden path"** → Build context is wrong, use project root
4. **Deployment scope mismatch** → Use `az deployment sub` for subscription scope, `az deployment group` for resource group scope

### Debugging Commands
```bash
# Check ACR build logs
az acr task logs -r $ACR_NAME --run-id $RUN_ID

# Verify container app status
az containerapp show -n $APP_NAME -g $RG_NAME --query properties.provisioningState

# Check role assignments
az role assignment list --assignee $PRINCIPAL_ID --resource-group $RG_NAME
```

## Region Support

Azure SRE Agent (Preview) is only available in:
- `eastus2`
- `swedencentral` ← This lab uses this region
- `uksouth`
- `australiaeast`

Always use one of these regions for `AZURE_LOCATION`.

## Reference Links

When suggesting code or solutions, reference:
- SRE Agent Docs: https://github.com/microsoft/sre-agent
- Octopets Sample: https://github.com/Azure-Samples/octopets
- Lab Specification: `specs/specs.md`
- ServiceNow Demo: `demos/ServiceNowAzureResourceHandler/README.md` and `specs/IncidentAutomationServiceNow.md`
- AzureHealthCheck Demo: `demos/AzureHealthCheck/README.md`
- Subagent YAMLs: 
  * ServiceNow: `demos/ServiceNowAzureResourceHandler/servicenow-subagent-simple.yaml`
  * Health Check: `demos/AzureHealthCheck/azurehealthcheck-subagent-simple.yaml`

## Development Environment

- **Container**: VS Code Dev Container (Debian Trixie)
- **Tools Pre-installed**: Azure CLI 2.74.0, azd 1.22.3, .NET SDK 9.0.308, Node.js 20.19.6
- **No Docker**: Dev container cannot run Docker, use ACR Tasks for builds

## Code Generation Preferences

When generating code for this project:

1. **Scripts**: Prefer bash over PowerShell
2. **IaC**: Use Bicep, not ARM JSON or Terraform
3. **Naming**: Follow Azure naming conventions (prefix-based)
4. **Paths**: Use absolute paths from `/workspaces/AzSreAgentLab/`
5. **Error Handling**: Always validate inputs and provide clear error messages
6. **Logging**: Echo progress for long-running operations

## Testing Workflow

1. Make changes to scripts or templates
2. Test in isolation before full deployment
3. Use `--what-if` for Bicep deployments
4. Verify with Azure CLI queries after deployment
5. Clean up test resources to avoid costs

---

**Remember**: This is a lab environment for testing Azure SRE Agent. Always scope permissions tightly and use Review mode before Autonomous mode in production scenarios.
