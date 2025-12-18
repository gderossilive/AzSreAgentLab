#!/usr/bin/env bash
set -euo pipefail

# Disable CPU stress in Octopets backend Container App
source scripts/load-env.sh

: "${OCTOPETS_RG_NAME:?Missing OCTOPETS_RG_NAME}"

echo "======================================"
echo "Disabling CPU Stress Test"
echo "======================================"
echo ""

echo "Setting CPU_STRESS=false on octopetsapi..."
az containerapp update \
  -n octopetsapi \
  -g "$OCTOPETS_RG_NAME" \
  --set-env-vars "CPU_STRESS=false"

echo ""
echo "✅ CPU stress DISABLED"
echo ""
echo "The backend will now operate normally without CPU-intensive operations."
echo ""
