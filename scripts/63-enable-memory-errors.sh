#!/usr/bin/env bash
set -euo pipefail

# Enable memory error injection in Octopets backend
# This causes the app to allocate excessive memory (1GB) on API calls

source "$(dirname "$0")/load-env.sh"

: "${OCTOPETS_RG_NAME:?Missing OCTOPETS_RG_NAME. Run deployment scripts first.}"

echo "Enabling MEMORY_ERRORS on octopetsapi..."
az containerapp update \
  --name octopetsapi \
  --resource-group "$OCTOPETS_RG_NAME" \
  --set-env-vars "MEMORY_ERRORS=true" \
  --output none

echo "✓ MEMORY_ERRORS enabled. The app will now allocate 1GB of memory on each API call."
echo "Generate traffic with: ./scripts/60-generate-traffic.sh 20"
echo "Disable with: ./scripts/64-disable-memory-errors.sh"
