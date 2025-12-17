#!/usr/bin/env bash
set -euo pipefail

# Generate traffic to Octopets application to trigger memory leak alerts
# Usage: ./60-generate-traffic.sh [duration_minutes]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/load-env.sh"

DURATION_MINUTES="${1:-10}"
REQUESTS_PER_MINUTE=30
SLEEP_SECONDS=$((60 / REQUESTS_PER_MINUTE))

: "${OCTOPETS_FE_URL:?Missing OCTOPETS_FE_URL}"
: "${OCTOPETS_API_URL:?Missing OCTOPETS_API_URL}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Generating Traffic to Octopets Application"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Configuration:"
echo "  Frontend URL:         $OCTOPETS_FE_URL"
echo "  API URL:              $OCTOPETS_API_URL"
echo "  Duration:             $DURATION_MINUTES minutes"
echo "  Requests/minute:      $REQUESTS_PER_MINUTE"
echo "  Sleep between calls:  ${SLEEP_SECONDS}s"
echo ""
echo "Press Ctrl+C to stop..."
echo ""

START_TIME=$(date +%s)
END_TIME=$((START_TIME + (DURATION_MINUTES * 60)))
REQUEST_COUNT=0

# Frontend URLs to simulate realistic user browsing
FE_URLS=(
    "/"
    "/listings?petType=dogs"
    "/listing/1"
    "/listing/2"
    "/listings?petType=cats"
    "/listing/3"
    "/listing/4"
)

# API endpoints to generate backend load
API_URLS=(
    "/api/products"
    "/api/products/1"
    "/api/products/2"
)

while true; do
    CURRENT_TIME=$(date +%s)
    
    # Check if duration exceeded
    if [ "$CURRENT_TIME" -ge "$END_TIME" ]; then
        echo ""
        echo "✓ Duration completed: $DURATION_MINUTES minutes"
        echo "✓ Total requests: $REQUEST_COUNT"
        break
    fi
    
    # Calculate progress
    ELAPSED=$((CURRENT_TIME - START_TIME))
    REMAINING=$((END_TIME - CURRENT_TIME))
    
    # Make requests
    REQUEST_COUNT=$((REQUEST_COUNT + 1))
    
    # Rotate through frontend URLs
    FE_INDEX=$((REQUEST_COUNT % ${#FE_URLS[@]}))
    FE_PATH="${FE_URLS[$FE_INDEX]}"
    
    # Frontend request
    if curl -s -o /dev/null -w "%{http_code}" "$OCTOPETS_FE_URL$FE_PATH" | grep -q "200"; then
        FE_STATUS="✓"
    else
        FE_STATUS="✗"
    fi
    
    # Rotate through API URLs
    API_INDEX=$((REQUEST_COUNT % ${#API_URLS[@]}))
    API_PATH="${API_URLS[$API_INDEX]}"
    
    # API request to products endpoint (generates backend load)
    if curl -s -o /dev/null -w "%{http_code}" "$OCTOPETS_API_URL$API_PATH" | grep -q "200"; then
        API_STATUS="✓"
    else
        API_STATUS="✗"
    fi
    
    # Progress update every 10 requests
    if [ $((REQUEST_COUNT % 10)) -eq 0 ]; then
        printf "\r[%02d:%02d] Request #%d - FE: %s (%s) API: %s (%s) [%02d:%02d left]" \
            $((ELAPSED / 60)) $((ELAPSED % 60)) \
            $REQUEST_COUNT \
            "$FE_STATUS" "$FE_PATH" \
            "$API_STATUS" "$API_PATH" \
            $((REMAINING / 60)) $((REMAINING % 60))
    fi
    
    sleep "$SLEEP_SECONDS"
done

echo ""
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Traffic Generation Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "  1. Monitor memory usage:"
echo "     az monitor metrics list \\"
echo "       --resource \"/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/rg-octopets-lab/providers/Microsoft.App/containerApps/octopetsapi\" \\"
echo "       --metric WorkingSetBytes --interval PT1M"
echo ""
echo "  2. Check for alerts:"
echo "     az monitor metrics alert list -g rg-octopets-lab -o table"
echo ""
echo "  3. Check ServiceNow for incidents:"
echo "     https://$SERVICENOW_INSTANCE.service-now.com/now/nav/ui/classic/params/target/incident_list.do"
echo ""
