#!/usr/bin/env bash
set -euo pipefail

# Deploy Grocery SRE Demo infrastructure + a dedicated SRE Agent.
# Writes demo-config.json (no secrets).

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_root="$(cd "$script_dir/.." && pwd)"
repo_root="$(cd "$demo_root/../.." && pwd)"
infra_dir="$demo_root/infrastructure"
config_path="$demo_root/demo-config.json"

log_step() { echo; echo "[STEP] $*"; }
log_ok() { echo "[OK] $*"; }
log_info() { echo "[INFO] $*"; }
log_err() { echo "[ERROR] $*" >&2; }

die() { log_err "$*"; exit 1; }

usage() {
  cat <<EOF
Usage: $0 [--resource-group <name>] [--environment-name <name>] [--location <region>] [--subscription-id <guid>] [--sre-agent-name <name>] [--sre-agent-access-level High|Low]

Defaults:
  --location:            swedencentral
  --resource-group:      rg-grocery-sre-demo
  --environment-name:    grocery-sre-demo
  --sre-agent-name:      sre-agent-grocery-demo
  --sre-agent-access-level: High
EOF
}

resource_group="rg-grocery-sre-demo"
environment_name="grocery-sre-demo"
location="swedencentral"
subscription_id=""
sre_agent_name="sre-agent-grocery-demo"
sre_agent_access_level="High"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group|-g)
      resource_group="${2:-}"; shift 2 ;;
    --environment-name)
      environment_name="${2:-}"; shift 2 ;;
    --location|-l)
      location="${2:-}"; shift 2 ;;
    --subscription-id|-s)
      subscription_id="${2:-}"; shift 2 ;;
    --sre-agent-name)
      sre_agent_name="${2:-}"; shift 2 ;;
    --sre-agent-access-level)
      sre_agent_access_level="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "Unknown argument: $1" ;;
  esac
done

command -v az >/dev/null 2>&1 || die "Azure CLI (az) not found"
command -v python3 >/dev/null 2>&1 || die "python3 not found (used for JSON parsing)"

log_step "Checking Azure CLI login"
az account show >/dev/null 2>&1 || die "Azure CLI not logged in. Run: az login"

if [[ -n "$subscription_id" ]]; then
  log_info "Setting subscription: $subscription_id"
  az account set --subscription "$subscription_id" >/dev/null
else
  subscription_id="$(az account show --query id -o tsv)"
  log_info "Using current subscription: $subscription_id"
fi

log_step "Deploying infrastructure + SRE Agent (subscription-scope Bicep)"
deployment_name="grocery-sre-demo-$(date -u +%Y%m%d%H%M%S)"
deployment_json="$(az deployment sub create \
  --name "$deployment_name" \
  --location "$location" \
  --template-file "$infra_dir/main.bicep" \
  --parameters environmentName="$environment_name" location="$location" resourceGroupName="$resource_group" sreAgentName="$sre_agent_name" sreAgentAccessLevel="$sre_agent_access_level" \
  --output json)"

get_output_value() {
  local output_name="$1"
  python3 -c "import json,sys; name=sys.argv[1]; j=json.load(sys.stdin); print(j['properties']['outputs'][name]['value'])" "$output_name" <<<"$deployment_json"
}

rg_name="$(get_output_value resourceGroupName)"
acr_name="$(get_output_value containerRegistryName)"
acr_login="$(get_output_value containerRegistryLoginServer)"
cae_name="$(get_output_value containerAppsEnvironmentName)"
api_app="$(get_output_value apiContainerAppName)"
web_app="$(get_output_value webContainerAppName)"
api_url="$(get_output_value apiUrl)"
web_url="$(get_output_value webUrl)"
grafana_name="$(get_output_value grafanaName)"
grafana_endpoint="$(get_output_value grafanaEndpoint)"
agent_portal_url="$(get_output_value sreAgentPortalUrl)"

log_ok "Deployed"
log_info "  Resource Group: $rg_name"
log_info "  ACR:           $acr_name ($acr_login)"
log_info "  CAE:           $cae_name"
log_info "  API URL:       $api_url"
log_info "  Web URL:       $web_url"
log_info "  Grafana:       $grafana_name ($grafana_endpoint)"
log_info "  SRE Agent:     $sre_agent_name"

log_step "Reading SRE Agent endpoint (may take a moment)"
sre_agent_endpoint=""
for _ in {1..18}; do
  sre_agent_endpoint="$(az resource show -g "$rg_name" -n "$sre_agent_name" --resource-type Microsoft.App/agents --query properties.agentEndpoint -o tsv 2>/dev/null || true)"
  if [[ -n "$sre_agent_endpoint" ]]; then
    break
  fi
  sleep 10
done

if [[ -z "$sre_agent_endpoint" ]]; then
  log_info "SRE Agent endpoint not available yet (still provisioning/building knowledge graph)."
else
  log_ok "SRE Agent endpoint: $sre_agent_endpoint"
fi

log_step "Writing demo config: $config_path"
python3 - "$config_path" <<PY
import json
import sys

path = sys.argv[1]

data = {
  "SubscriptionId": "${subscription_id}",
  "Location": "${location}",
  "EnvironmentName": "${environment_name}",
  "ResourceGroupName": "${rg_name}",
  "ContainerAppsEnvironmentName": "${cae_name}",
  "ContainerRegistryName": "${acr_name}",
  "ContainerRegistryLoginServer": "${acr_login}",
  "ApiContainerAppName": "${api_app}",
  "WebContainerAppName": "${web_app}",
  "ApiUrl": "${api_url}",
  "WebUrl": "${web_url}",
  "GrafanaName": "${grafana_name}",
  "GrafanaEndpoint": "${grafana_endpoint}",
  "SreAgentName": "${sre_agent_name}",
  "SreAgentEndpoint": "${sre_agent_endpoint}",
  "SreAgentPortalUrl": "${agent_portal_url}",
}

with open(path, 'w', encoding='utf-8') as f:
  json.dump(data, f, indent=2)
  f.write("\n")

print("Wrote demo-config.json")
PY

log_ok "Setup complete"
log_info "Next: $demo_root/scripts/02-build-and-deploy-containers.sh"
