#!/usr/bin/env bash
set -euo pipefail

# Print the public base URL for the Octopets backend (Container App)
# Useful for Azure Load Testing (hosted JMeter) and manual testing.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/load-env.sh"

: "${OCTOPETS_RG_NAME:?Missing OCTOPETS_RG_NAME}"
: "${OCTOPETS_API_APP_NAME:=octopetsapi}"

if ! az account show >/dev/null 2>&1; then
  echo "ERROR: Azure CLI is not logged in. Run: az login" >&2
  exit 1
fi

FQDN="$(
  az containerapp show \
    -n "${OCTOPETS_API_APP_NAME}" \
    -g "${OCTOPETS_RG_NAME}" \
    --query "properties.configuration.ingress.fqdn" \
    -o tsv
)"

if [[ -z "${FQDN}" ]]; then
  echo "ERROR: Could not determine ingress FQDN for ${OCTOPETS_API_APP_NAME} (is ingress enabled?)" >&2
  exit 1
fi

echo "Octopets API base URL:" 
echo "https://${FQDN}"

if [[ -n "${OCTOPETS_API_URL:-}" ]]; then
  echo "" 
  echo "(From .env OCTOPETS_API_URL:)"
  echo "${OCTOPETS_API_URL}"
fi
