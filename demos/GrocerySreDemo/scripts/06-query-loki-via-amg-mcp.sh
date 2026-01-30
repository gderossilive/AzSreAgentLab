#!/usr/bin/env bash
set -euo pipefail

# Run a Loki LogQL query via Azure Managed Grafana using the existing MCP server binary (`amg-mcp`)
# in stdio mode (no Managed Grafana “remote MCP endpoint” required), without using `az containerapp exec`.
#
# Approach:
# - Build a small runner image in ACR that includes `amg-mcp` + a Python MCP stdio client.
# - Deploy an ephemeral Container App (no ingress) that uses the existing `uami-mcp-amg` managed identity.
# - Fetch the Container App logs to see datasource discovery + query output.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_root="$(cd "$script_dir/.." && pwd)"
repo_root="$(cd "$demo_root/../.." && pwd)"
config_path="$demo_root/demo-config.json"

template="$demo_root/infrastructure/amg-mcp-loki-query-runner.bicep"
runner_dockerfile="$demo_root/docker/loki-query-runner.Dockerfile"

log_step() { echo; echo "[STEP] $*"; }
log_ok() { echo "[OK] $*"; }
log_info() { echo "[INFO] $*"; }
log_err() { echo "[ERROR] $*" >&2; }

die() { log_err "$*"; exit 1; }

command -v az >/dev/null 2>&1 || die "Azure CLI (az) not found"
command -v python3 >/dev/null 2>&1 || die "python3 not found (used for JSON parsing)"

[[ -f "$config_path" ]] || die "Missing $config_path. Run demos/GrocerySreDemo/scripts/01-setup-demo.sh first."
[[ -f "$template" ]] || die "Missing template: $template"
[[ -f "$runner_dockerfile" ]] || die "Missing runner Dockerfile: $runner_dockerfile"

subscription_id="$(python3 -c "import json; print(json.load(open('$config_path'))['SubscriptionId'])")"
rg_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ResourceGroupName'])")"
cae_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ContainerAppsEnvironmentName'])")"
grafana_endpoint="$(python3 -c "import json; print(json.load(open('$config_path'))['GrafanaEndpoint'].rstrip('/'))")"
acr_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ContainerRegistryName'])")"
location="$(python3 -c "import json; print(json.load(open('$config_path'))['Location'])")"

lookback_minutes=15
logql='{app="grocery-api"}'
limit=20
keep=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lookback-minutes)
      lookback_minutes="$2"; shift 2;;
    --logql)
      logql="$2"; shift 2;;
    --limit)
      limit="$2"; shift 2;;
    --keep)
      keep=true; shift;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --lookback-minutes N   How far back to query (default: 15)
  --logql '...'          LogQL expression (default: {app="grocery-api"})
  --limit N              Best-effort log limit (default: 20)
  --keep                 Do not delete the ephemeral runner app
EOF
      exit 0;;
    *)
      die "Unknown arg: $1";;
  esac
done

az account show >/dev/null 2>&1 || die "Azure CLI not logged in. Run: az login"
az account set --subscription "$subscription_id" >/dev/null

log_step "Building runner image in ACR (remote build)"
az acr build \
  --registry "$acr_name" \
  --image "amg-mcp-loki-query-runner:latest" \
  --file "$runner_dockerfile" \
  --build-arg "ACR_LOGIN_SERVER=${acr_name}.azurecr.io" \
  "$repo_root" \
  --output none

log_step "Resolving Container Apps environment ID"
environment_id="$(az containerapp env show -g "$rg_name" -n "$cae_name" --query id -o tsv)"
[[ -n "$environment_id" ]] || die "Unable to resolve environmentId for $cae_name"

runner_app_name="ca-amg-loki-q-$(date -u +%y%m%d%H%M%S)"
deployment_name="grocery-amg-mcp-loki-query-$(date -u +%Y%m%d%H%M%S)"

log_step "Deploying ephemeral runner Container App: $runner_app_name"
az deployment group create \
  --name "$deployment_name" \
  --resource-group "$rg_name" \
  --template-file "$template" \
  --parameters location="$location" environmentId="$environment_id" acrName="$acr_name" grafanaEndpoint="$grafana_endpoint" \
    appName="$runner_app_name" lookbackMinutes="$lookback_minutes" lokiLogQl="$logql" limit="$limit" \
  --output none

log_ok "Deployed. Waiting briefly for logs to populate..."
sleep 15

log_step "Runner logs (tail)"
az containerapp logs show -g "$rg_name" -n "$runner_app_name" --tail 200 || true

if [[ "$keep" == "true" ]]; then
  log_ok "Keeping runner app: $runner_app_name"
  log_info "Delete later with: az containerapp delete -g $rg_name -n $runner_app_name -y"
else
  log_step "Deleting runner app: $runner_app_name"
  az containerapp delete -g "$rg_name" -n "$runner_app_name" -y --output none || true
  log_ok "Deleted runner app"
fi
