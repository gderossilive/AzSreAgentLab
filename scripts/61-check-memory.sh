#!/usr/bin/env bash
set -euo pipefail

# Check octopets API memory usage using REST API
# Usage: ./61-check-memory.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/load-env.sh"

: "${AZURE_SUBSCRIPTION_ID:?Missing AZURE_SUBSCRIPTION_ID}"

RESOURCE_ID="/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/rg-octopets-lab/providers/Microsoft.App/containerApps/octopetsapi"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Checking Octopets API Memory Usage"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get container app details
echo "Container App Status:"
az containerapp show -n octopetsapi -g rg-octopets-lab \
  --query '{Name:name, Status:properties.runningStatus, Replicas:properties.template.scale.minReplicas, Memory:properties.template.containers[0].resources.memory}' \
  -o table

echo ""
echo "Current Revision:"
az containerapp revision list -n octopetsapi -g rg-octopets-lab \
  --query '[0].{Revision:name, Active:properties.active, Replicas:properties.replicas, Traffic:properties.trafficWeight}' \
  -o table

echo ""
echo "Environment Variables:"
az containerapp show -n octopetsapi -g rg-octopets-lab \
  --query 'properties.template.containers[0].env[?name==`ERRORS`]' \
  -o table

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Monitor Memory in Azure Portal:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Portal URL:"
echo "   https://portal.azure.com/#@$AZURE_TENANT_ID/resource$RESOURCE_ID/metrics"
echo ""
echo "2. Check alerts:"
echo "   https://portal.azure.com/#view/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/~/alertsV2"
echo ""
echo "3. ServiceNow incidents:"
echo "   https://${SERVICENOW_INSTANCE}.service-now.com/now/nav/ui/classic/params/target/incident_list.do"
echo ""
