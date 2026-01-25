#!/usr/bin/env bash
set -euo pipefail

# Enable memory error injection in Octopets backend
# This causes the app to allocate excessive memory (1GB) on API calls
# INC0010041: Added production safeguards to prevent accidental enablement

source "$(dirname "$0")/load-env.sh"

: "${OCTOPETS_RG_NAME:?Missing OCTOPETS_RG_NAME. Run deployment scripts first.}"

# Container app name (configurable via env or default to octopetsapi)
container_app_name="${OCTOPETS_API_APP_NAME:-octopetsapi}"

# Check the container app's actual ASPNETCORE_ENVIRONMENT setting
echo "Checking container app environment..."
container_env=$(az containerapp show \
  --name "$container_app_name" \
  --resource-group "$OCTOPETS_RG_NAME" \
  --query "properties.template.containers[?name=='$container_app_name'].env[?name=='ASPNETCORE_ENVIRONMENT'].value | [0] | [0]" \
  -o tsv 2>/dev/null || echo "")

# If ASPNETCORE_ENVIRONMENT is not set, check local env or default to Production
env_type="${container_env:-${ASPNETCORE_ENVIRONMENT:-Production}}"

if [[ "$env_type" == "Production" ]]; then
  echo "❌ ERROR: Cannot enable MEMORY_ERRORS in Production environment!"
  echo "This is a demo/testing feature that causes severe memory issues (INC0010041)."
  echo ""
  echo "The container app is currently configured with ASPNETCORE_ENVIRONMENT=Production."
  echo "To use this demo feature, first redeploy with a non-production environment setting."
  echo ""
  exit 1
fi

# Additional confirmation prompt
echo "⚠️  WARNING: This will enable memory stress testing (allocates 1GB per API call)"
echo "Resource Group: $OCTOPETS_RG_NAME"
echo "Container App: $container_app_name"
echo "Environment: $env_type"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirmation

if [[ "$confirmation" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

echo "Enabling MEMORY_ERRORS on $container_app_name..."
az containerapp update \
  --name "$container_app_name" \
  --resource-group "$OCTOPETS_RG_NAME" \
  --set-env-vars "MEMORY_ERRORS=true" \
  --output none

echo "✓ MEMORY_ERRORS enabled. The app will now allocate 1GB of memory on each API call."
echo "Generate traffic with: ./scripts/60-generate-traffic.sh 20"
echo "Disable with: ./scripts/64-disable-memory-errors.sh"
