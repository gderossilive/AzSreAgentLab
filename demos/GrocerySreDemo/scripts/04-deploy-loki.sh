#!/usr/bin/env bash
set -euo pipefail

# Optional: Deploy Loki as a Container App and configure the Grocery API to push logs to it.
# No secrets are written.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_root="$(cd "$script_dir/.." && pwd)"
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
api_app_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ApiContainerAppName'])")"
location="$(python3 -c "import json; print(json.load(open('$config_path'))['Location'])")"

az account show >/dev/null 2>&1 || die "Azure CLI not logged in. Run: az login"
az account set --subscription "$subscription_id" >/dev/null

loki_app_name="ca-loki"

log_step "Deploying Loki Container App: $loki_app_name"
if az containerapp show -g "$rg_name" -n "$loki_app_name" >/dev/null 2>&1; then
  log_info "Loki app already exists; updating image/config"
  az containerapp update -g "$rg_name" -n "$loki_app_name" \
    --image grafana/loki:2.9.0 \
    --min-replicas 1 --max-replicas 1 >/dev/null
else
  az containerapp create \
    --name "$loki_app_name" \
    --resource-group "$rg_name" \
    --environment "$cae_name" \
    --image grafana/loki:2.9.0 \
    --target-port 3100 \
    --ingress external \
    --min-replicas 1 \
    --max-replicas 1 \
    --cpu 0.5 \
    --memory 1Gi \
    >/dev/null
fi

loki_fqdn="$(az containerapp show -g "$rg_name" -n "$loki_app_name" --query properties.configuration.ingress.fqdn -o tsv)"
[[ -n "$loki_fqdn" ]] || die "Unable to read Loki FQDN"
loki_host="https://${loki_fqdn}"

log_ok "Loki endpoint: $loki_host"

log_step "Configuring Grocery API to push logs to Loki"
az containerapp update -g "$rg_name" -n "$api_app_name" \
  --set-env-vars "LOKI_HOST=$loki_host" >/dev/null

log_ok "Configured $api_app_name LOKI_HOST=$loki_host"
log_info "Tip: trigger a few 503s via scripts/03-smoke-and-trigger.sh, then query Loki in Grafana using knowledge/loki-queries.md"
