#!/usr/bin/env bash
set -euo pipefail

# Enable CPU stress in Octopets backend Container App
source scripts/load-env.sh

: "${OCTOPETS_RG_NAME:?Missing OCTOPETS_RG_NAME}"

echo "======================================"
echo "Enabling CPU Stress Test"
echo "======================================"
echo ""

echo "Setting CPU_STRESS=true on octopetsapi..."
az containerapp update \
  -n octopetsapi \
  -g "$OCTOPETS_RG_NAME" \
  --set-env-vars "CPU_STRESS=true"

echo ""
echo "✅ CPU stress ENABLED"
echo ""
echo "The backend will now perform CPU-intensive operations on each request."
echo "Each request will consume ~500ms of CPU time with mathematical computations."
echo ""
echo "To trigger CPU anomaly detection:"
echo "  1. Generate traffic: ./scripts/60-generate-traffic.sh 50"
echo "  2. Wait for metrics aggregation (5-15 minutes)"
echo "  3. Trigger health check agent or wait for scheduled run"
echo ""
echo "To disable CPU stress:"
echo "  ./scripts/62-disable-cpu-stress.sh"
echo ""
