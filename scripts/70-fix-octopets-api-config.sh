#!/usr/bin/env bash
set -euo pipefail

# Fix Octopets API Container App configuration to resolve 5xx errors
# This script updates the running Container App with:
# 1. Disabled fault injection flags (CPU_STRESS=false, MEMORY_ERRORS=false)
# 2. Health probes (liveness and readiness)
# 3. Increased minReplicas to 2 for high availability
# 4. Improved OTEL telemetry configuration
#
# Usage:
#   source scripts/load-env.sh
#   scripts/70-fix-octopets-api-config.sh

: "${OCTOPETS_RG_NAME:?Missing OCTOPETS_RG_NAME}"

API_APP="octopetsapi"

echo "======================================"
echo "Fixing Octopets API Configuration"
echo "======================================"
echo ""

if ! az account show >/dev/null 2>&1; then
  echo "ERROR: Azure CLI is not logged in. Run: az login" >&2
  exit 1
fi

# Get Application Insights connection string
APP_INSIGHTS_CONN_STR=$(az monitor app-insights component list \
  -g "$OCTOPETS_RG_NAME" \
  --query "[0].connectionString" -o tsv)

if [[ -z "$APP_INSIGHTS_CONN_STR" ]]; then
  echo "WARNING: Could not find Application Insights connection string"
  APP_INSIGHTS_CONN_STR=""
fi

echo "Step 1: Disabling fault injection flags..."
az containerapp update \
  -n "$API_APP" \
  -g "$OCTOPETS_RG_NAME" \
  --container-name "$API_APP" \
  --set-env-vars \
    "CPU_STRESS=false" \
    "MEMORY_ERRORS=false" \
    "OTEL_METRICS_EXPORTER=otlp" \
    "OTEL_LOGS_EXPORTER=otlp" \
    "APPLICATIONINSIGHTS_CONNECTION_STRING=$APP_INSIGHTS_CONN_STR" \
  --output none

echo "✓ Fault injection disabled"
echo ""

echo "Step 2: Configuring health probes..."
# Note: Health probes must be configured via YAML or Bicep
# Using az containerapp update with --yaml option
cat > /tmp/octopetsapi-probes.yaml <<EOF
properties:
  template:
    containers:
    - name: $API_APP
      probes:
      - type: Liveness
        httpGet:
          path: /health
          port: 8080
          scheme: HTTP
        initialDelaySeconds: 10
        periodSeconds: 30
        failureThreshold: 3
        successThreshold: 1
        timeoutSeconds: 5
      - type: Readiness
        httpGet:
          path: /health
          port: 8080
          scheme: HTTP
        initialDelaySeconds: 5
        periodSeconds: 10
        failureThreshold: 3
        successThreshold: 1
        timeoutSeconds: 3
EOF

az containerapp update \
  -n "$API_APP" \
  -g "$OCTOPETS_RG_NAME" \
  --yaml /tmp/octopetsapi-probes.yaml \
  --output none

echo "✓ Health probes configured"
echo ""

echo "Step 3: Increasing replica count for high availability..."
az containerapp update \
  -n "$API_APP" \
  -g "$OCTOPETS_RG_NAME" \
  --min-replicas 2 \
  --max-replicas 10 \
  --output none

echo "✓ Scaling configured (min: 2, max: 10)"
echo ""

echo "======================================"
echo "✅ Configuration Update Complete"
echo "======================================"
echo ""
echo "Changes applied:"
echo "  • CPU_STRESS and MEMORY_ERRORS set to false"
echo "  • OTEL_METRICS_EXPORTER and OTEL_LOGS_EXPORTER set to otlp"
echo "  • Liveness probe: GET /health on port 8080"
echo "  • Readiness probe: GET /health on port 8080"
echo "  • Min replicas: 2 (increased from 1)"
echo "  • Max replicas: 10 (increased from 1)"
echo ""
echo "Monitoring recommendations:"
echo "  1. Monitor Container Apps Requests metric for 30-60 minutes"
echo "  2. Verify 5xx errors have decreased"
echo "  3. Check replica health and probe success rates"
echo "  4. Review Application Insights for request/exception telemetry"
echo ""

# Clean up temp file
rm -f /tmp/octopetsapi-probes.yaml
