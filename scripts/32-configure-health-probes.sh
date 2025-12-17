#!/usr/bin/env bash
set -euo pipefail

# Configure health probes for Octopets API container app
# Run this after 31-deploy-octopets-containers.sh
#
# Usage:
#   source scripts/load-env.sh
#   scripts/32-configure-health-probes.sh

: "${OCTOPETS_RG_NAME:?Missing OCTOPETS_RG_NAME}"

api_app="octopetsapi"

echo "Configuring health probes for $api_app..."

# Get current container app configuration
current_config=$(az containerapp show -g "$OCTOPETS_RG_NAME" -n "$api_app" -o json)

# Extract necessary values
revision_suffix=$(echo "$current_config" | jq -r '.properties.template.revisionSuffix // ""')
subscription_id=$(az account show --query id -o tsv)

# Create a YAML configuration with health probes
cat > /tmp/containerapp-probes.yaml <<EOF
properties:
  template:
    containers:
    - name: $api_app
      probes:
      - type: Liveness
        httpGet:
          path: /health/live
          port: 8080
          scheme: HTTP
        initialDelaySeconds: 30
        periodSeconds: 10
        failureThreshold: 3
        timeoutSeconds: 5
      - type: Readiness
        httpGet:
          path: /health/ready
          port: 8080
          scheme: HTTP
        initialDelaySeconds: 5
        periodSeconds: 5
        failureThreshold: 3
        timeoutSeconds: 3
EOF

echo "Applying health probe configuration..."

# Use Azure REST API to patch the container app
az rest \
  --method PATCH \
  --uri "/subscriptions/${subscription_id}/resourceGroups/${OCTOPETS_RG_NAME}/providers/Microsoft.App/containerApps/${api_app}?api-version=2024-03-01" \
  --body @/tmp/containerapp-probes.yaml

echo "Health probes configured successfully!"
echo "Liveness probe: /health/live (every 10s after 30s initial delay)"
echo "Readiness probe: /health/ready (every 5s after 5s initial delay)"
