#!/usr/bin/env bash
set -euo pipefail

# Deploy an Azure Monitor scheduled query alert for supplier rate-limit events (SUPPLIER_RATE_LIMIT_429)
# in the Grocery API Container App logs.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_root="$(cd "$script_dir/.." && pwd)"
infra_dir="$demo_root/infrastructure"
config_path="$demo_root/demo-config.json"

log_step() { echo; echo "[STEP] $*"; }
log_ok() { echo "[OK] $*"; }
log_info() { echo "[INFO] $*"; }
log_err() { echo "[ERROR] $*" >&2; }

die() { log_err "$*"; exit 1; }

usage() {
  cat <<EOF
Usage: $0 [--action-group-id <resourceId>] [--email <address>] [--threshold <n>] [--severity 0-4]

Reads from: $config_path
Deploys: scheduled query alert rule to the demo resource group

Options:
  --action-group-id   Existing Action Group resource ID to notify (optional)
  --email             Creates a new Action Group with an email receiver (optional)
  --threshold         Number of log hits in window to trigger (default: 1)
  --severity          0-4 where 0 is most severe (default: 2)
EOF
}

action_group_id=""
email_address=""
threshold="1"
severity="2"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action-group-id)
      action_group_id="${2:-}"; shift 2 ;;
    --email)
      email_address="${2:-}"; shift 2 ;;
    --threshold)
      threshold="${2:-}"; shift 2 ;;
    --severity)
      severity="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "Unknown argument: $1" ;;
  esac
done

command -v az >/dev/null 2>&1 || die "Azure CLI (az) not found"
command -v python3 >/dev/null 2>&1 || die "python3 not found (used for JSON parsing)"

[[ -f "$config_path" ]] || die "Missing $config_path. Run scripts/01-setup-demo.sh first."

subscription_id="$(python3 -c "import json; print(json.load(open('$config_path'))['SubscriptionId'])")"
rg_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ResourceGroupName'])")"
api_app="$(python3 -c "import json; print(json.load(open('$config_path'))['ApiContainerAppName'])")"

log_step "Checking Azure CLI login"
az account show >/dev/null 2>&1 || die "Azure CLI not logged in. Run: az login"

log_info "Setting subscription: $subscription_id"
az account set --subscription "$subscription_id" >/dev/null

log_step "Discovering Log Analytics workspace in $rg_name"
workspace_id="$(az resource list -g "$rg_name" --resource-type "Microsoft.OperationalInsights/workspaces" --query "[0].id" -o tsv)"

if [[ -z "$workspace_id" ]]; then
  die "No Log Analytics workspace found in resource group $rg_name"
fi

log_ok "Workspace: $workspace_id"

log_step "Deploying scheduled query alert (SUPPLIER_RATE_LIMIT_429)"
deployment_name="grocery-supplier-429-alert-$(date -u +%Y%m%d%H%M%S)"

deploy_log="$(mktemp)"
if ! az deployment group create \
  --name "$deployment_name" \
  --resource-group "$rg_name" \
  --template-file "$infra_dir/az-monitor-alerts-supplier-429.bicep" \
  --parameters \
      apiContainerAppName="$api_app" \
      logAnalyticsWorkspaceResourceId="$workspace_id" \
      actionGroupResourceId="$action_group_id" \
      alertEmailAddress="$email_address" \
      threshold="$threshold" \
      severity="$severity" \
  --only-show-errors \
  --output none \
  >"$deploy_log" 2>&1; then
  log_err "Alert deployment failed. Last output:"
  tail -n 200 "$deploy_log" >&2 || true
  rm -f "$deploy_log" || true
  exit 1
fi

rm -f "$deploy_log" || true

log_ok "Alert deployed"
log_info "Tip: trigger the scenario (scripts/03-smoke-and-trigger.sh) and then check the alert rule state in Azure Portal."
