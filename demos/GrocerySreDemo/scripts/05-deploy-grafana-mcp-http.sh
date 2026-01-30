#!/usr/bin/env bash
set -euo pipefail

# Deploy a Grafana MCP server with an HTTP endpoint ("streamable-http") as a Container App.
#
# This is the "connectable from an MCP client" variant:
#   https://<fqdn>/mcp
#
# IMPORTANT:
# - Requires a Grafana service account token.
# - Do NOT commit tokens to git.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_root="$(cd "$script_dir/.." && pwd)"
config_path="$demo_root/demo-config.json"

template="$demo_root/infrastructure/mcp-grafana-http.bicep"

log_step() { echo; echo "[STEP] $*"; }
log_ok() { echo "[OK] $*"; }
log_info() { echo "[INFO] $*"; }
log_err() { echo "[ERROR] $*" >&2; }

die() { log_err "$*"; exit 1; }

command -v az >/dev/null 2>&1 || die "Azure CLI (az) not found"
command -v python3 >/dev/null 2>&1 || die "python3 not found (used for JSON parsing)"

[[ -f "$config_path" ]] || die "Missing $config_path. Run scripts/01-setup-demo.sh first."
[[ -f "$template" ]] || die "Missing template: $template"

# Args
GRAFANA_TOKEN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --grafana-token)
      GRAFANA_TOKEN="${2:-}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage:
  ./scripts/05-deploy-grafana-mcp-http.sh --grafana-token "glsa_..."

Or set an env var (recommended in your shell history hygiene):
  export GRAFANA_SERVICE_ACCOUNT_TOKEN="glsa_..."
  ./scripts/05-deploy-grafana-mcp-http.sh
EOF
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

if [[ -z "$GRAFANA_TOKEN" ]]; then
  GRAFANA_TOKEN="${GRAFANA_SERVICE_ACCOUNT_TOKEN:-}"
fi

[[ -n "$GRAFANA_TOKEN" ]] || die "Missing Grafana token. Provide --grafana-token or set GRAFANA_SERVICE_ACCOUNT_TOKEN (do not commit it)."

subscription_id="$(python3 -c "import json; print(json.load(open('$config_path'))['SubscriptionId'])")"
rg_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ResourceGroupName'])")"
cae_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ContainerAppsEnvironmentName'])")"
grafana_endpoint="$(python3 -c "import json; print(json.load(open('$config_path'))['GrafanaEndpoint'])")"
location="$(python3 -c "import json; print(json.load(open('$config_path'))['Location'])")"

az account show >/dev/null 2>&1 || die "Azure CLI not logged in. Run: az login"
az account set --subscription "$subscription_id" >/dev/null

log_step "Resolving Container Apps environment ID"
environment_id="$(az containerapp env show -g "$rg_name" -n "$cae_name" --query id -o tsv)"
[[ -n "$environment_id" ]] || die "Unable to resolve environmentId for $cae_name"

deployment_name="grocery-grafana-mcp-http-$(date -u +%Y%m%d%H%M%S)"

log_step "Deploying HTTP Grafana MCP server (ca-mcp-grafana)"
az deployment group create \
  --name "$deployment_name" \
  --resource-group "$rg_name" \
  --template-file "$template" \
  --parameters location="$location" environmentId="$environment_id" grafanaUrl="$grafana_endpoint" grafanaToken="$GRAFANA_TOKEN" \
  --query "properties.outputs" -o json

fqdn="$(az containerapp show -g "$rg_name" -n ca-mcp-grafana --query properties.configuration.ingress.fqdn -o tsv)"

log_ok "Deployed. MCP endpoint: https://$fqdn/mcp"
log_info "Transport: streamable-http"
"