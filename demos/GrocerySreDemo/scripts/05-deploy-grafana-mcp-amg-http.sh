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

log_step "Ensuring Azure Managed Grafana CLI extension is available"
az extension add --name amg --upgrade --only-show-errors >/dev/null || true

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

# Optional AMW Prometheus direct query fallback: discover AMW query endpoint if present.
amw_query_endpoint=""
amw_name=""
amw_names="$(az resource list -g "$rg_name" --resource-type Microsoft.Monitor/accounts --query "[].name" -o tsv 2>/dev/null || true)"
if [[ -n "$amw_names" ]]; then
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    candidate_endpoint="$(az resource show -g "$rg_name" -n "$candidate" --resource-type Microsoft.Monitor/accounts --query properties.metrics.prometheusQueryEndpoint -o tsv 2>/dev/null || true)"
    if [[ -n "$candidate_endpoint" ]]; then
      amw_name="$candidate"
      amw_query_endpoint="${candidate_endpoint%/}"
      log_info "Detected AMW Prometheus query endpoint: $amw_query_endpoint"
      break
    fi
  done <<< "$amw_names"
fi

# Optional Prometheus datasource UID: used for Grafana datasource-proxy queries.
prometheus_datasource_name="Prometheus (AMW)"
prometheus_datasource_uid=""

resolve_prometheus_uid() {
  local uid
  uid="$(az grafana data-source list -g "$rg_name" -n "$grafana_name" --query "[?name=='$prometheus_datasource_name'].uid | [0]" -o tsv 2>/dev/null || true)"
  if [[ -z "$uid" && -n "${amw_query_endpoint:-}" ]]; then
    uid="$(az grafana data-source list -g "$rg_name" -n "$grafana_name" --query "[?type=='prometheus' && url=='${amw_query_endpoint}'].uid | [0]" -o tsv 2>/dev/null || true)"
  fi
  echo "$uid"
}

prometheus_datasource_uid="$(resolve_prometheus_uid)"

# If we detected AMW but the Prometheus datasource isn't present (or UID lookup failed),
# create/update it via the dedicated script so the MCP proxy can use Grafana's datasource
# proxy fast path without depending on AMW direct queries.
if [[ -z "$prometheus_datasource_uid" && -n "${amw_query_endpoint:-}" ]]; then
  log_step "Ensuring Prometheus (AMW) datasource exists in Managed Grafana"
  "$demo_root/scripts/07-create-custom-grafana-dashboard.sh" \
    --prometheus-only \
    --prometheus-datasource-name "$prometheus_datasource_name" \
    ${amw_name:+--amw-name "$amw_name"} \
    --amw-query-endpoint "$amw_query_endpoint"

  prometheus_datasource_uid="$(resolve_prometheus_uid)"
fi

if [[ -n "$prometheus_datasource_uid" ]]; then
  log_info "Detected Grafana Prometheus datasource UID: $prometheus_datasource_uid"
else
  log_info "Grafana Prometheus datasource UID not detected (continuing without it)"
fi

az deployment group create \
  --name "$deployment_name" \
  --resource-group "$rg_name" \
  --template-file "$template" \
  --parameters location="$location" environmentId="$environment_id" acrName="$acr_name" grafanaName="$grafana_name" grafanaEndpoint="$grafana_endpoint" lokiEndpoint="$loki_endpoint" amwQueryEndpoint="$amw_query_endpoint" prometheusDatasourceUid="$prometheus_datasource_uid" imageTag="$image_tag" deploymentStamp="$deployment_name" \
  --query "properties.outputs" -o json > /tmp/mcp-proxy-deploy-outputs.json

principal_id="$(python3 -c "import json; print(json.load(open('/tmp/mcp-proxy-deploy-outputs.json')).get('principalId', {}).get('value', ''))")"
mcp_url="$(python3 -c "import json; print(json.load(open('/tmp/mcp-proxy-deploy-outputs.json')).get('mcpUrl', {}).get('value', ''))")"

# If AMW is present and we are using AMW direct PromQL fallback, the Container App's managed identity
# must have permission to query Prometheus metrics.
if [[ -n "$amw_name" && -n "$amw_query_endpoint" && -n "$principal_id" ]]; then
  log_step "Granting MCP proxy MI access to AMW Prometheus metrics"
  amw_id="$(az resource show -g "$rg_name" -n "$amw_name" --resource-type Microsoft.Monitor/accounts --query id -o tsv)"

  if [[ -z "$amw_id" ]]; then
    die "Unable to resolve AMW resource ID for $amw_name"
  fi

  existing_count="$(az role assignment list --assignee "$principal_id" --scope "$amw_id" --query "[?roleDefinitionName=='Monitoring Data Reader'] | length(@)" -o tsv 2>/dev/null || echo 0)"
  if [[ "$existing_count" == "0" ]]; then
    az role assignment create --assignee-object-id "$principal_id" --assignee-principal-type ServicePrincipal --role "Monitoring Data Reader" --scope "$amw_id" --output none
    log_ok "Assigned 'Monitoring Data Reader' on AMW to principalId=$principal_id"
  else
    log_ok "Role assignment already present for principalId=$principal_id"
  fi
fi

fqdn="$(az containerapp show -g "$rg_name" -n ca-mcp-amg-proxy --query properties.configuration.ingress.fqdn -o tsv)"

log_ok "Deployed. MCP endpoint: https://$fqdn/mcp"
log_info "Transport: streamable-http"
log_info "Auth: managed identity (Grafana Viewer RBAC on the Managed Grafana resource)"

if [[ -n "$mcp_url" ]]; then
  log_info "Deployment output MCP URL: $mcp_url"
fi

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
