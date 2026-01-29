#!/usr/bin/env bash
set -euo pipefail

# Optional: Deploy an MCP server for **Azure Managed Grafana** as a Container App.
#
# Note: Some Azure Managed Grafana instances have Grafana “service accounts / tokens” disabled.
# This script uses the MI-based `amg-mcp` server instead of the token-based `mcp-grafana` server.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_root="$(cd "$script_dir/.." && pwd)"
repo_root="$(cd "$demo_root/../.." && pwd)"
config_path="$demo_root/demo-config.json"

log_step() { echo; echo "[STEP] $*"; }
log_ok() { echo "[OK] $*"; }
log_info() { echo "[INFO] $*"; }
log_err() { echo "[ERROR] $*" >&2; }

die() { log_err "$*"; exit 1; }

command -v az >/dev/null 2>&1 || die "Azure CLI (az) not found"
command -v python3 >/dev/null 2>&1 || die "python3 not found (used for JSON parsing)"

[[ -f "$config_path" ]] || die "Missing $config_path. Run scripts/01-setup-demo.sh first."

subscription_id="$(python3 -c "import json; print(json.load(open('$config_path'))['SubscriptionId'])")"
rg_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ResourceGroupName'])")"
cae_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ContainerAppsEnvironmentName'])")"
grafana_endpoint="$(python3 -c "import json; print(json.load(open('$config_path'))['GrafanaEndpoint'])")"
grafana_name="$(python3 -c "import json; print(json.load(open('$config_path'))['GrafanaName'])")"
acr_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ContainerRegistryName'])")"
location="$(python3 -c "import json; print(json.load(open('$config_path'))['Location'])")"

az account show >/dev/null 2>&1 || die "Azure CLI not logged in. Run: az login"
az account set --subscription "$subscription_id" >/dev/null

log_step "Resolving Container Apps environment ID"
environment_id="$(az containerapp env show -g "$rg_name" -n "$cae_name" --query id -o tsv)"
[[ -n "$environment_id" ]] || die "Unable to resolve environmentId for $cae_name"

if az containerapp show -g "$rg_name" -n ca-mcp-amg --query "properties.provisioningState" -o tsv >/dev/null 2>&1; then
  existing_state="$(az containerapp show -g "$rg_name" -n ca-mcp-amg --query "properties.provisioningState" -o tsv)"
  if [[ "$existing_state" == "Failed" ]]; then
    log_step "Deleting existing failed Container App ca-mcp-amg"
    az containerapp delete -g "$rg_name" -n ca-mcp-amg -y --output none
  fi
fi

log_step "Remote build: amg-mcp image in ACR"
dockerfile_path="$repo_root/external/grocery-sre-demo/infra/amg-mcp/Dockerfile"
[[ -f "$dockerfile_path" ]] || die "Missing Dockerfile: $dockerfile_path"

az acr show -n "$acr_name" -g "$rg_name" >/dev/null

az acr build \
  --registry "$acr_name" \
  --image amg-mcp:latest \
  --file "$dockerfile_path" \
  "$repo_root" \
  --output none

template="$demo_root/infrastructure/mcp-amg.bicep"
[[ -f "$template" ]] || die "Missing template: $template"

deployment_name="grocery-amg-mcp-$(date -u +%Y%m%d%H%M%S)"

log_step "Deploying Azure Managed Grafana MCP server (ca-mcp-amg)"
az deployment group create \
  --name "$deployment_name" \
  --resource-group "$rg_name" \
  --template-file "$template" \
  --parameters location="$location" environmentId="$environment_id" acrName="$acr_name" grafanaName="$grafana_name" grafanaEndpoint="$grafana_endpoint" \
  --output none

mcp_fqdn="$(az containerapp show -g "$rg_name" -n ca-mcp-amg --query properties.configuration.ingress.fqdn -o tsv)"
if [[ -n "$mcp_fqdn" ]]; then
  log_ok "AMG MCP SSE endpoint: https://${mcp_fqdn}/sse"
else
  log_ok "Deployed. (Unable to read MCP FQDN yet; check the container app 'ca-mcp-amg' in the portal.)"
fi

log_info "Auth note: this uses the Container App managed identity with the 'Grafana Viewer' Azure RBAC role on the Managed Grafana resource."
