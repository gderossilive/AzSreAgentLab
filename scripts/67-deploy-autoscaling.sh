#!/usr/bin/env bash
set -euo pipefail

# Deploy auto-scaling configuration for Octopets Container Apps
# INC0010041: Enables KEDA-based auto-scaling to handle memory pressure and traffic spikes
#
# Region: Sweden Central is required for SRE Agent preview compatibility
#
# Usage:
#   source scripts/load-env.sh
#   scripts/67-deploy-autoscaling.sh

source "$(dirname "$0")/load-env.sh"

: "${AZURE_SUBSCRIPTION_ID:?Missing AZURE_SUBSCRIPTION_ID}"
: "${OCTOPETS_RG_NAME:?Missing OCTOPETS_RG_NAME}"

# Use AZURE_LOCATION from env or default to swedencentral (SRE Agent preview requirement)
location="${AZURE_LOCATION:-swedencentral}"

echo "Deploying auto-scaling configuration for Octopets API..."

az deployment group create \
  --resource-group "$OCTOPETS_RG_NAME" \
  --template-file demos/ServiceNowAzureResourceHandler/octopets-autoscaling.bicep \
  --parameters \
    subscriptionId="$AZURE_SUBSCRIPTION_ID" \
    resourceGroupName="$OCTOPETS_RG_NAME" \
    backendAppName="octopetsapi" \
    location="${location}" \
    minReplicas=1 \
    maxReplicas=3 \
    cpuScaleThreshold=70 \
    memoryScaleThreshold=70 \
    httpConcurrentRequestsThreshold=10

echo "✓ Auto-scaling configuration deployed successfully!"
echo ""
echo "Configuration:"
echo "  - Min Replicas: 1"
echo "  - Max Replicas: 3"
echo "  - CPU Scale Threshold: 70%"
echo "  - Memory Scale Threshold: 70%"
echo "  - HTTP Concurrent Requests: 10"
echo ""
echo "The container app will now automatically scale based on CPU, memory, and HTTP traffic."
