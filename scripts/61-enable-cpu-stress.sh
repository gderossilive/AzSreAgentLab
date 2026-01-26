#!/usr/bin/env bash
set -euo pipefail

# Enable CPU stress in Octopets backend Container App
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/load-env.sh"

: "${OCTOPETS_RG_NAME:?Missing OCTOPETS_RG_NAME}"
: "${OCTOPETS_API_APP_NAME:=octopetsapi}"

echo "======================================"
echo "Enabling CPU Stress Test"
echo "======================================"
echo ""

if ! az account show >/dev/null 2>&1; then
  echo "ERROR: Azure CLI is not logged in. Run: az login" >&2
  exit 1
fi

echo "Setting CPU_STRESS=true on ${OCTOPETS_API_APP_NAME}..."
az containerapp update \
  -n "${OCTOPETS_API_APP_NAME}" \
  -g "$OCTOPETS_RG_NAME" \
  --container-name "${OCTOPETS_API_APP_NAME}" \
  --set-env-vars "CPU_STRESS=true"

echo ""
echo "✅ CPU stress ENABLED"
echo ""
echo "The backend will now perform CPU-intensive operations on each request."
echo "Each request will consume ~500ms of CPU time with mathematical computations."
echo ""
echo "To trigger CPU anomaly detection:"
echo "  Option A (local curl):"
echo "    1. Generate traffic: ./scripts/60-generate-traffic.sh 10"
echo ""
echo "  Option B (Azure Load Testing = hosted JMeter):"
echo "    1. Get API URL:       ./scripts/59-print-octopetsapi-url.sh"
echo "    2. Upload JMX plan:   loadtests/jmeter/octopetsapi-cpu-stress.jmx"
echo "    3. Follow:            docs/azure-load-testing-jmeter.md"
echo ""
echo "Then wait for metrics aggregation (5-15 minutes) and trigger health checks."
echo ""
echo "To disable CPU stress:"
echo "  ./scripts/62-disable-cpu-stress.sh"
echo ""
