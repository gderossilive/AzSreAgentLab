#!/usr/bin/env bash
set -euo pipefail

# Deploy Octopets infrastructure via Bicep (no azd/Docker required).
#
# Usage:
#   source scripts/load-env.sh
#   scripts/20-az-login.sh
#   scripts/30-deploy-octopets.sh

: "${AZURE_SUBSCRIPTION_ID:?Missing AZURE_SUBSCRIPTION_ID}"
: "${AZURE_LOCATION:?Missing AZURE_LOCATION}"
: "${OCTOPETS_ENV_NAME:?Missing OCTOPETS_ENV_NAME}"

# Verify Azure CLI login
az account show >/dev/null 2>&1 || {
  echo "ERROR: Not logged in to Azure CLI. Run scripts/20-az-login.sh first." >&2
  exit 1
}

# Deploy infrastructure using the generated Bicep (no Docker needed)
echo "Deploying Octopets infrastructure via Azure CLI..."

# Deploy Bicep at subscription scope (it creates the resource group)
az deployment sub create \
  -l "$AZURE_LOCATION" \
  -f external/octopets/apphost/infra/main.bicep \
  -p environmentName="$OCTOPETS_ENV_NAME" \
  -p location="$AZURE_LOCATION"

# Update .env with the resource group name
rg_name="rg-${OCTOPETS_ENV_NAME}"
"${PWD}/scripts/set-dotenv-value.sh" "OCTOPETS_RG_NAME" "$rg_name"
"${PWD}/scripts/set-dotenv-value.sh" "SRE_AGENT_TARGET_RESOURCE_GROUPS" "$rg_name"

echo "Octopets infrastructure deployed successfully!"
echo "Resource Group: $rg_name"
echo "Next: scripts/31-deploy-octopets-containers.sh"
