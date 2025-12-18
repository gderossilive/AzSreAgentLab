#!/usr/bin/env bash
set -euo pipefail

# Disable memory error injection in Octopets backend

source "$(dirname "$0")/load-env.sh"

: "${OCTOPETS_RG_NAME:?Missing OCTOPETS_RG_NAME. Run deployment scripts first.}"

echo "Disabling MEMORY_ERRORS on octopetsapi..."
az containerapp update \
  --name octopetsapi \
  --resource-group "$OCTOPETS_RG_NAME" \
  --set-env-vars "MEMORY_ERRORS=false" \
  --output none

echo "✓ MEMORY_ERRORS disabled. The app is now running normally."
