#!/usr/bin/env bash
set -euo pipefail

# Deploy Azure SRE Agent using the reference repo's Bicep templates/scripts.
# Usage:
#   source scripts/load-env.sh
#   scripts/10-clone-repos.sh
#   scripts/20-az-login.sh
#   # after Octopets deployment:
#   # set OCTOPETS_RG_NAME and SRE_AGENT_TARGET_RESOURCE_GROUPS in .env
#   scripts/40-deploy-sre-agent.sh

: "${AZURE_SUBSCRIPTION_ID:?Missing AZURE_SUBSCRIPTION_ID}"
: "${AZURE_LOCATION:?Missing AZURE_LOCATION}"
: "${SRE_AGENT_RG_NAME:?Missing SRE_AGENT_RG_NAME}"
: "${SRE_AGENT_NAME:?Missing SRE_AGENT_NAME}"
: "${SRE_AGENT_ACCESS_LEVEL:?Missing SRE_AGENT_ACCESS_LEVEL}"
: "${SRE_AGENT_TARGET_RESOURCE_GROUPS:?Missing SRE_AGENT_TARGET_RESOURCE_GROUPS}"

pushd external/sre-agent/samples/bicep-deployment/scripts >/dev/null

chmod +x ./*.sh

# The deploy script accepts a comma-separated list via -t; we pass exactly one RG.
./deploy.sh --no-interactive \
  -s "$AZURE_SUBSCRIPTION_ID" \
  -r "$SRE_AGENT_RG_NAME" \
  -n "$SRE_AGENT_NAME" \
  -l "$AZURE_LOCATION" \
  -a "$SRE_AGENT_ACCESS_LEVEL" \
  -t "$SRE_AGENT_TARGET_RESOURCE_GROUPS"

popd >/dev/null
