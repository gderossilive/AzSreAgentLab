#!/usr/bin/env bash
set -euo pipefail

# Deploy an Azure Managed Grafana MCP endpoint that is CONNECTABLE from MCP clients.
#
# This uses managed identity (no Grafana service account token) by:
# - Running the official `amg-mcp` binary in stdio mode
# - Exposing a streamable-HTTP MCP server that proxies requests to that stdio backend
#
# Result:
#   https://<fqdn>/mcp

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
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

dockerfile_path="$demo_root/docker/amg-mcp-http-proxy.Dockerfile"
[[ -f "$dockerfile_path" ]] || die "Missing Dockerfile: $dockerfile_path"

template="$demo_root/infrastructure/mcp-amg-http-proxy.bicep"
[[ -f "$template" ]] || die "Missing template: $template"

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

log_step "Remote build: amg-mcp-http-proxy image in ACR"
az acr show -n "$acr_name" -g "$rg_name" >/dev/null

image_tag="$(date -u +%Y%m%d%H%M%S)"
log_info "Image tag: $image_tag"

az acr build \
  --registry "$acr_name" \
  --image "amg-mcp-http-proxy:${image_tag}" \
  --file "$dockerfile_path" \
  --build-arg ACR_LOGIN_SERVER="${acr_name}.azurecr.io" \
  "$repo_root" \
  --output none

deployment_name="grocery-amg-mcp-http-proxy-$(date -u +%Y%m%d%H%M%S)"

log_step "Deploying MI-based HTTP MCP endpoint (ca-mcp-amg-proxy)"

# Optional Loki direct query fallback: discover the Loki Container App FQDN if present.
loki_endpoint=""
if az containerapp show -g "$rg_name" -n ca-loki --query name -o tsv >/dev/null 2>&1; then
  loki_fqdn="$(az containerapp show -g "$rg_name" -n ca-loki --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || true)"
  if [[ -n "$loki_fqdn" ]]; then
    loki_endpoint="https://$loki_fqdn"
    log_info "Detected Loki endpoint: $loki_endpoint"
  fi
fi

az deployment group create \
  --name "$deployment_name" \
  --resource-group "$rg_name" \
  --template-file "$template" \
  --parameters location="$location" environmentId="$environment_id" acrName="$acr_name" grafanaName="$grafana_name" grafanaEndpoint="$grafana_endpoint" lokiEndpoint="$loki_endpoint" imageTag="$image_tag" deploymentStamp="$deployment_name" \
  --query "properties.outputs" -o json

fqdn="$(az containerapp show -g "$rg_name" -n ca-mcp-amg-proxy --query properties.configuration.ingress.fqdn -o tsv)"

log_ok "Deployed. MCP endpoint: https://$fqdn/mcp"
log_info "Transport: streamable-http"
log_info "Auth: managed identity (Grafana Viewer RBAC on the Managed Grafana resource)"

log_step "Waiting for revision to become Healthy"
latest_rev="$(az containerapp show -g "$rg_name" -n ca-mcp-amg-proxy --query properties.latestRevisionName -o tsv)"
[[ -n "$latest_rev" ]] || die "Unable to read latestRevisionName for ca-mcp-amg-proxy"
for i in {1..30}; do
  health_state="$(az containerapp revision show -g "$rg_name" -n ca-mcp-amg-proxy --revision "$latest_rev" --query properties.healthState -o tsv 2>/dev/null || true)"
  replicas="$(az containerapp revision show -g "$rg_name" -n ca-mcp-amg-proxy --revision "$latest_rev" --query properties.replicas -o tsv 2>/dev/null || true)"
  if [[ "$health_state" == "Healthy" ]]; then
    log_ok "Revision $latest_rev is Healthy (replicas=$replicas)"
    break
  fi
  log_info "Revision $latest_rev healthState=$health_state replicas=$replicas (waiting...)"
  sleep 5
done
