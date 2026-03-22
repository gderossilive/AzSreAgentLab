#!/usr/bin/env bash
set -euo pipefail

# Loads .env into the current shell.
# Usage:
#   source scripts/load-env.sh

if [[ ! -f "${PWD}/.env" ]]; then
  echo "ERROR: .env not found in ${PWD}. Create it from .env.example." >&2
  return 1 2>/dev/null || exit 1
fi

set -a
# shellcheck disable=SC1091
source "${PWD}/.env"
set +a

: "${AZURE_TENANT_ID:?Missing AZURE_TENANT_ID}"
: "${AZURE_SUBSCRIPTION_ID:?Missing AZURE_SUBSCRIPTION_ID}"
: "${AZURE_LOCATION:?Missing AZURE_LOCATION}"

echo "Loaded .env (tenant=$AZURE_TENANT_ID, sub=$AZURE_SUBSCRIPTION_ID, location=$AZURE_LOCATION)"
