#!/usr/bin/env bash
# Deploy Azure Monitor metric alert rules for Octopets Container Apps (octopetsfe + octopetsapi)
#
# This deploys metric alerts only (CPU, response time, 5xx).
# - No secrets required
# - Optional notifications: set ALERT_ACTION_GROUP_ID to an existing Action Group resource ID
#
# Usage:
#   source scripts/load-env.sh
#   ./scripts/66-deploy-octopets-metric-alerts.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Load env (keeps secrets out of stdout)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/load-env.sh"

: "${AZURE_SUBSCRIPTION_ID:?Missing AZURE_SUBSCRIPTION_ID}"
: "${OCTOPETS_RG_NAME:?Missing OCTOPETS_RG_NAME}"

BICEP_FILE="$REPO_ROOT/demos/AzureHealthCheck/octopets-az-monitor-alerts.bicep"
if [[ ! -f "$BICEP_FILE" ]]; then
  echo "ERROR: Bicep template not found at $BICEP_FILE" >&2
  exit 1
fi

# Optional Action Group (leave empty for no notifications)
ALERT_ACTION_GROUP_ID="${ALERT_ACTION_GROUP_ID:-}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Deploying Octopets Metric Alerts (FE + API)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Configuration:"
echo "  Subscription:   $AZURE_SUBSCRIPTION_ID"
echo "  Resource Group: $OCTOPETS_RG_NAME"
if [[ -n "$ALERT_ACTION_GROUP_ID" ]]; then
  echo "  Action Group:   $ALERT_ACTION_GROUP_ID"
else
  echo "  Action Group:   (none)"
fi

# Check Azure auth
if ! az account show >/dev/null 2>&1; then
  echo "ERROR: Not logged in to Azure. Run az login (or scripts/20-az-login.sh) first." >&2
  exit 1
fi

az account set --subscription "$AZURE_SUBSCRIPTION_ID" >/dev/null

DEPLOYMENT_NAME="octopets-metric-alerts-$(date +%Y%m%d-%H%M%S)"

PARAMS=(
  "subscriptionId=$AZURE_SUBSCRIPTION_ID"
  "resourceGroupName=$OCTOPETS_RG_NAME"
)

if [[ -n "$ALERT_ACTION_GROUP_ID" ]]; then
  PARAMS+=("actionGroupResourceId=$ALERT_ACTION_GROUP_ID")
fi

echo ""
echo "Deploying: $DEPLOYMENT_NAME"

az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$OCTOPETS_RG_NAME" \
  --template-file "$BICEP_FILE" \
  --parameters "${PARAMS[@]}" \
  --output none

echo ""
echo "✓ Deployment complete"
echo ""
echo "Verify metric alerts (without az monitor module):"
echo "  az resource list -g $OCTOPETS_RG_NAME --resource-type Microsoft.Insights/metricAlerts --query '[].name' -o table"
