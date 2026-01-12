# Copilot Instructions — AzSreAgentLab (Project Constitution)

## Constitution (always true for this repo)
- Purpose: Lab environment to deploy Octopets + Azure SRE Agent (Preview) and run demos (ServiceNow incident automation, scheduled health checks).
- Environment: VS Code devcontainer on Linux; do not assume local Docker.
- Builds: Use ACR remote builds (`az acr build`) when building containers; use repo root as build context.
- IaC: Prefer Bicep; use correct deployment scope (subscription vs resource group).
- Region: Default/expected region is `swedencentral` (SRE Agent preview region constraint).
- Security: Least privilege always; never grant subscription-wide permissions to the agent; scope RBAC to target resource group(s) only.
- Secrets: Never commit `.env` or secrets.
- Vendored sources: `external/` is vendored reference content; treat as read-only unless explicitly asked to re-vendor/update.

## Project Memory (per-instance state)
- Use `.docs/memory.md` as the instance-specific memory (deployment state, RG names, URLs, connector notes, known issues, next steps).
- `.docs/memory.md` is gitignored and should not be committed.
- Before doing work: read `.docs/memory.md`.
- After making decisions/deployments: update `.docs/memory.md`.

## Coding Defaults
- Bash: use `set -euo pipefail`, validate required env vars (`: "${VAR:?Missing VAR}"`), print progress.
- Keep changes minimal: implement only what the user asked; avoid unrelated refactors.
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
