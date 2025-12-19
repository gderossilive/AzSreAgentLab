#!/usr/bin/env bash
# Deploy Azure Monitor CPU alert rule for Octopets Container App
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/load-env.sh"

: "${AZURE_SUBSCRIPTION_ID:?Missing AZURE_SUBSCRIPTION_ID}"
: "${OCTOPETS_RG_NAME:?Missing OCTOPETS_RG_NAME}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Deploying CPU Alert Rule for Octopets API"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get Container App resource ID
BACKEND_APP_ID=$(az containerapp show -n octopetsapi -g "$OCTOPETS_RG_NAME" --query id -o tsv)
echo "Backend App ID: $BACKEND_APP_ID"
echo ""

# Create action group for email notifications (if it doesn't exist)
ACTION_GROUP_NAME="CPUAlerts-ActionGroup"
if ! az monitor action-group show -n "$ACTION_GROUP_NAME" -g "$OCTOPETS_RG_NAME" &>/dev/null; then
  echo "Creating action group for notifications..."
  az monitor action-group create \
    -n "$ACTION_GROUP_NAME" \
    -g "$OCTOPETS_RG_NAME" \
    --short-name "CPUAlerts" \
    --output none
  echo "✓ Action group created"
else
  echo "✓ Action group already exists"
fi
echo ""

# Create CPU alert rule
# Container Apps are allocated 0.5 CPU cores = 500,000,000 nanocores
# 70% of 0.5 cores = 350,000,000 nanocores
# 80% of 0.5 cores = 400,000,000 nanocores
ALERT_NAME="High CPU Usage - Octopets API"
CPU_THRESHOLD=350000000  # 70% of 0.5 cores

echo "Creating CPU alert rule..."
echo "  Alert Name: $ALERT_NAME"
echo "  Threshold: 70% CPU (350,000,000 nanocores)"
echo "  Evaluation: Every 1 minute"
echo "  Window: 5 minutes"
echo ""

az monitor metrics alert create \
  --name "$ALERT_NAME" \
  --resource-group "$OCTOPETS_RG_NAME" \
  --scopes "$BACKEND_APP_ID" \
  --condition "avg UsageNanoCores > $CPU_THRESHOLD" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 2 \
  --description "Triggers when backend container app CPU usage exceeds 70% for 5 minutes" \
  --action "$ACTION_GROUP_NAME" \
  --auto-mitigate true \
  --output none

echo "✓ CPU alert rule created successfully"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Alert Rule Deployment Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Alert Configuration:"
echo "  Metric: UsageNanoCores"
echo "  Threshold: 70% CPU (350,000,000 nanocores)"
echo "  Evaluation: Every 1 minute over 5 minute window"
echo "  Severity: Warning (2)"
echo "  Action Group: $ACTION_GROUP_NAME"
echo ""
echo "To test the alert:"
echo "  1. Enable CPU stress:    ./scripts/61-enable-cpu-stress.sh"
echo "  2. Generate traffic:     ./scripts/60-generate-traffic.sh 10"
echo "  3. Wait 5-10 minutes for alert to fire"
echo "  4. Check alert status:   az monitor metrics alert show -n '$ALERT_NAME' -g $OCTOPETS_RG_NAME"
echo "  5. Disable CPU stress:   ./scripts/62-disable-cpu-stress.sh"
echo ""
echo "Monitor alert activity:"
echo "  az monitor activity-log list -g $OCTOPETS_RG_NAME --caller 'Microsoft.Insights/metricAlerts' --max-events 10 -o table"
echo ""
