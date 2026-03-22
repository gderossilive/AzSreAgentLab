#!/usr/bin/env bash
# sre-agent-power.sh — Start or stop Azure SRE Agents (Microsoft.App/agents)
#
# Usage:
#   sre-agent-power.sh {start|stop} [--subscription SUB_ID] [-g RESOURCE_GROUP] [-n AGENT_NAME]
#
# Examples:
#   sre-agent-power.sh start                          # start all agents in current subscription
#   sre-agent-power.sh stop  -g rg-grubify-lab        # stop all agents in one RG
#   sre-agent-power.sh start -g rg-grubify-lab -n sre-agent-cff6qws2yy4ku

set -euo pipefail

API_VERSION="2025-05-01-preview"

# ── Parse arguments ──────────────────────────────────────────────────────────
ACTION="${1:-}"
shift || true

if [[ -z "$ACTION" || ( "$ACTION" != "start" && "$ACTION" != "stop" ) ]]; then
  echo "Usage: $(basename "$0") {start|stop} [--subscription SUB_ID] [-g RESOURCE_GROUP] [-n AGENT_NAME]" >&2
  exit 1
fi

SUB_ID=""
FILTER_RG=""
FILTER_NAME=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --subscription|-s) SUB_ID="$2";     shift 2 ;;
    --resource-group|-g) FILTER_RG="$2"; shift 2 ;;
    --name|-n) FILTER_NAME="$2";        shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$SUB_ID" ]] && SUB_ID=$(az account show --query id -o tsv)

echo "Subscription : $SUB_ID"
echo "Action       : $ACTION"
[[ -n "$FILTER_RG"   ]] && echo "Filter RG    : $FILTER_RG"
[[ -n "$FILTER_NAME" ]] && echo "Filter Name  : $FILTER_NAME"
echo ""

# ── Discover agents ───────────────────────────────────────────────────────────
LIST_ARGS=(--subscription "$SUB_ID" --resource-type Microsoft.App/agents --query "[].id" -o tsv)
[[ -n "$FILTER_RG"   ]] && LIST_ARGS+=(--resource-group "$FILTER_RG")
[[ -n "$FILTER_NAME" ]] && LIST_ARGS+=(--name "$FILTER_NAME")

mapfile -t AGENT_IDS < <(az resource list "${LIST_ARGS[@]}" 2>/dev/null | grep -v '^$' || true)

if [[ ${#AGENT_IDS[@]} -eq 0 ]]; then
  echo "No SRE Agents found."
  exit 0
fi

echo "Found ${#AGENT_IDS[@]} agent(s)"

SUCCEEDED=0; SKIPPED=0; FAILED=0

# ── Process each agent ────────────────────────────────────────────────────────
for AGENT_ID in "${AGENT_IDS[@]}"; do
  [[ -z "$AGENT_ID" ]] && continue

  # Fetch full agent properties using the correct API version
  AGENT_JSON=$(az rest --method GET \
    --url "https://management.azure.com${AGENT_ID}?api-version=${API_VERSION}" \
    -o json 2>/dev/null)

  AGENT_NAME=$(echo "$AGENT_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")
  POWER_STATE=$(echo "$AGENT_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d['properties'].get('powerState') or 'Unknown')
")

  # Extract resource group from ARM resource ID
  AGENT_RG=$(echo "$AGENT_ID" | python3 -c "
import sys, re
m = re.search(r'/resourceGroups/([^/]+)/', sys.stdin.read(), re.IGNORECASE)
print(m.group(1) if m else 'unknown')
")

  echo "── $AGENT_NAME  (rg: $AGENT_RG)  powerState: $POWER_STATE"

  # Skip agents already in the desired state
  if [[ "$ACTION" == "start" && "$POWER_STATE" == "Running" ]]; then
    echo "   Already running — skipping"
    (( SKIPPED++ )) || true
    continue
  fi

  if [[ "$ACTION" == "stop" && "$POWER_STATE" == "Stopped" ]]; then
    echo "   Already stopped — skipping"
    (( SKIPPED++ )) || true
    continue
  fi

  # ── Send start / stop ────────────────────────────────────────────────────
  # Note: POST /start works even when logConfiguration.connectionString is null.
  # The InvalidApplicationInsightsConfiguration error only occurs with `az resource update
  # --set properties.powerState`, NOT with the dedicated /start action endpoint.
  echo -n "   POST /$ACTION ... "
  ERR=$(az rest --method POST \
    --url "https://management.azure.com${AGENT_ID}/${ACTION}?api-version=${API_VERSION}" \
    -o json 2>&1 > /dev/null) && RC=0 || RC=$?
  if [[ $RC -eq 0 ]]; then
    echo "✓"
    (( SUCCEEDED++ )) || true
  else
    echo "✗ FAILED — $ERR"
    (( FAILED++ )) || true
  fi

done

echo ""
echo "═══════════════════════════════════════"
echo " Succeeded: $SUCCEEDED  Skipped: $SKIPPED  Failed: $FAILED"
