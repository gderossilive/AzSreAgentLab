#!/usr/bin/env bash
set -euo pipefail

# Deploy a tiny Prometheus-on-Container-Apps scraper that:
# - scrapes ca-api /metrics
# - probes ca-web via blackbox exporter
# - forwards metrics to Azure Monitor Workspace (Managed Prometheus) via remote_write
#   using a managed identity (Monitoring Metrics Publisher on the workspace DCR).

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

[[ -f "$config_path" ]] || die "Missing $config_path. Run demos/GrocerySreDemo/scripts/01-setup-demo.sh first."

template="$demo_root/infrastructure/prometheus-amw-monitoring.bicep"
[[ -f "$template" ]] || die "Missing template: $template"

acr_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ContainerRegistryName'])")"
subscription_id="$(python3 -c "import json; print(json.load(open('$config_path'))['SubscriptionId'])")"
rg_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ResourceGroupName'])")"
cae_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ContainerAppsEnvironmentName'])")"
location="$(python3 -c "import json; print(json.load(open('$config_path'))['Location'])")"
api_url="$(python3 -c "import json; print(json.load(open('$config_path'))['ApiUrl'])")"
web_url="$(python3 -c "import json; print(json.load(open('$config_path'))['WebUrl'])")"

api_fqdn="$(python3 -c "import urllib.parse; print(urllib.parse.urlparse('$api_url').netloc)")"
web_fqdn="$(python3 -c "import urllib.parse; print(urllib.parse.urlparse('$web_url').netloc)")"

amw_name=""
app_name="ca-prom-amw-monitoring"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --amw-name)
      amw_name="$2"; shift 2 ;;
    --app-name)
      app_name="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--amw-name <amw-name>] [--app-name <container-app-name>]

Defaults:
  --amw-name  (auto-detect first Microsoft.Monitor/accounts in $rg_name)
  --app-name  ca-prom-amw-monitoring
EOF
      exit 0
      ;;
    *)
      die "Unknown arg: $1" ;;
  esac
done

az account show >/dev/null 2>&1 || die "Azure CLI not logged in. Run: az login"
az account set --subscription "$subscription_id" >/dev/null

log_step "Resolving Container Apps environment ID"
environment_id="$(az containerapp env show -g "$rg_name" -n "$cae_name" --query id -o tsv)"
[[ -n "$environment_id" ]] || die "Unable to resolve environmentId for $cae_name"

if [[ -z "$amw_name" ]]; then
  log_step "Auto-detecting Azure Monitor Workspace (AMW) in $rg_name"
  amw_name="$(az resource list -g "$rg_name" --resource-type Microsoft.Monitor/accounts --query "[0].name" -o tsv)"
fi
[[ -n "$amw_name" ]] || die "Unable to find an Azure Monitor Workspace (Microsoft.Monitor/accounts) in $rg_name. Pass --amw-name."

log_step "Reading AMW ingestion artifacts (DCE + DCR)"
amw_json="$(az resource show -g "$rg_name" -n "$amw_name" --resource-type Microsoft.Monitor/accounts -o json)"
dce_id="$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['properties']['defaultIngestionSettings']['dataCollectionEndpointResourceId'])" <<<"$amw_json")"
dcr_id="$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['properties']['defaultIngestionSettings']['dataCollectionRuleResourceId'])" <<<"$amw_json")"
[[ -n "$dce_id" ]] || die "AMW defaultIngestionSettings.dataCollectionEndpointResourceId is empty"
[[ -n "$dcr_id" ]] || die "AMW defaultIngestionSettings.dataCollectionRuleResourceId is empty"

log_step "Resolving DCE metrics ingestion endpoint"
dce_endpoint="$(az resource show --ids "$dce_id" --query properties.metricsIngestion.endpoint -o tsv)"
[[ -n "$dce_endpoint" ]] || die "Unable to read DCE metricsIngestion.endpoint"

log_step "Resolving DCR immutableId"
dcr_immutable_id="$(az resource show --ids "$dcr_id" --query properties.immutableId -o tsv)"
[[ -n "$dcr_immutable_id" ]] || die "Unable to read DCR immutableId"

ingestion_url="${dce_endpoint}/dataCollectionRules/${dcr_immutable_id}/streams/Microsoft-PrometheusMetrics/api/v1/write?api-version=2023-04-24"
log_info "Computed ingestion URL: $ingestion_url"

log_step "Remote build images in ACR"
az acr show -n "$acr_name" -g "$rg_name" >/dev/null

image_tag="$(date -u +%Y%m%d%H%M%S)"
log_info "Image tag: $image_tag"

az acr build \
  --registry "$acr_name" \
  --image "prom-remote-write-proxy:${image_tag}" \
  --file "$demo_root/docker/prom-remote-write-proxy.Dockerfile" \
  "$repo_root" \
  --output none

az acr build \
  --registry "$acr_name" \
  --image "grocery-blackbox-exporter:${image_tag}" \
  --file "$demo_root/docker/grocery-blackbox-exporter.Dockerfile" \
  "$repo_root" \
  --output none

az acr build \
  --registry "$acr_name" \
  --image "grocery-prometheus:${image_tag}" \
  --file "$demo_root/docker/grocery-prometheus.Dockerfile" \
  --build-arg "API_FQDN=${api_fqdn}" \
  --build-arg "WEB_FQDN=${web_fqdn}" \
  "$repo_root" \
  --output none

log_step "Deploying Prometheus monitoring Container App (no ingress)"
deployment_name="grocery-prom-amw-monitoring-$(date -u +%Y%m%d%H%M%S)"

outputs_json="$(az deployment group create \
  --name "$deployment_name" \
  --resource-group "$rg_name" \
  --template-file "$template" \
  --parameters location="$location" environmentId="$environment_id" acrName="$acr_name" appName="$app_name" imageTag="$image_tag" ingestionUrl="$ingestion_url" deploymentStamp="$deployment_name" \
  --query "properties.outputs" -o json)"

principal_id="$(python3 -c "import json,sys; o=json.loads(sys.stdin.read()); print(o['principalId']['value'])" <<<"$outputs_json")"
[[ -n "$principal_id" ]] || die "Unable to read principalId output"

log_step "Granting Monitoring Metrics Publisher on the workspace DCR"
# Per official docs, the role assignment must be on the AMW's Data Collection Rule.
# Note: it can take ~30 minutes to take effect.
az role assignment create \
  --assignee-object-id "$principal_id" \
  --assignee-principal-type ServicePrincipal \
  --role "Monitoring Metrics Publisher" \
  --scope "$dcr_id" \
  --output none \
  || log_info "Role assignment may already exist (continuing)"

log_step "Waiting for revision to become Healthy"
latest_rev="$(az containerapp show -g "$rg_name" -n "$app_name" --query properties.latestRevisionName -o tsv)"
[[ -n "$latest_rev" ]] || die "Unable to read latestRevisionName for $app_name"

for i in {1..30}; do
  health_state="$(az containerapp revision show -g "$rg_name" -n "$app_name" --revision "$latest_rev" --query properties.healthState -o tsv 2>/dev/null || true)"
  replicas="$(az containerapp revision show -g "$rg_name" -n "$app_name" --revision "$latest_rev" --query properties.replicas -o tsv 2>/dev/null || true)"
  if [[ "$health_state" == "Healthy" ]]; then
    log_ok "Revision $latest_rev is Healthy (replicas=$replicas)"
    break
  fi
  log_info "Revision $latest_rev healthState=$health_state replicas=$replicas (waiting...)"
  sleep 5
done

log_ok "Deployed Container App: $app_name"
log_info "Scrape target: https://$api_fqdn/metrics"
log_info "Probe target:  https://$web_fqdn/"
log_info "PromQL (in Managed Grafana / AMW):"
log_info "  up{job=\"ca-api\"}"
log_info "  probe_success{job=\"blackbox-http\"}"
log_info "If you see 403s in logs, wait ~30 minutes for RBAC propagation."
