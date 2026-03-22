#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   source scripts/load-env.sh
#   scripts/20-az-login.sh

: "${AZURE_TENANT_ID:?Missing AZURE_TENANT_ID}"
: "${AZURE_SUBSCRIPTION_ID:?Missing AZURE_SUBSCRIPTION_ID}"

az login --tenant "$AZURE_TENANT_ID"
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
az account show --query "{tenantId:tenantId, subscriptionId:id, name:name, user:user.name}" -o json
