#!/usr/bin/env bash
set -euo pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Send Sample Anomaly Alert to Teams
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Sends a realistic anomaly alert to demonstrate what the Health Check
# agent will send when it detects issues.
# Usage: ./scripts/71-send-sample-anomaly.sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/load-env.sh"

# Validate required environment variables
: "${TEAMS_WEBHOOK_URL:?Missing TEAMS_WEBHOOK_URL. Please set it in .env file.}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Sending Sample Anomaly Alert to Teams"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create realistic anomaly alert payload (Adaptive Card format)
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
TIMEFRAME_START=$(date -u -d '24 hours ago' +"%Y-%m-%d %H:%M UTC")
TIMEFRAME_END=$(date -u +"%Y-%m-%d %H:%M UTC")

PAYLOAD=$(cat <<EOF
{
  "type": "message",
  "attachments": [
    {
      "contentType": "application/vnd.microsoft.card.adaptive",
      "content": {
        "type": "AdaptiveCard",
        "version": "1.4",
        "\$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
        "body": [
          {
            "type": "TextBlock",
            "text": "⚠️ Azure Health Check Alert",
            "size": "Large",
            "weight": "Bolder",
            "color": "Attention"
          },
          {
            "type": "TextBlock",
            "text": "Anomaly Detected",
            "size": "Medium",
            "weight": "Bolder",
            "spacing": "Small"
          },
          {
            "type": "TextBlock",
            "text": "Resource health threshold exceeded",
            "spacing": "None",
            "isSubtle": true
          },
          {
            "type": "FactSet",
            "spacing": "Medium",
            "facts": [
              {
                "title": "Resource:",
                "value": "octopetsapi (Container App)"
              },
              {
                "title": "Resource Group:",
                "value": "${OCTOPETS_RG_NAME:-rg-octopets-lab}"
              },
              {
                "title": "Metric:",
                "value": "Working Set Memory"
              },
              {
                "title": "Observed Value:",
                "value": "95% (1.02 GB / 1.07 GB limit)"
              },
              {
                "title": "Baseline:",
                "value": "65% (24h average)"
              },
              {
                "title": "Threshold:",
                "value": "3σ exceeded (z-score: 4.2)"
              },
              {
                "title": "Timeframe:",
                "value": "$TIMEFRAME_START → $TIMEFRAME_END"
              },
              {
                "title": "Status:",
                "value": "🔴 ANOMALY DETECTED"
              },
              {
                "title": "Detection Time:",
                "value": "$TIMESTAMP"
              }
            ]
          },
          {
            "type": "TextBlock",
            "text": "**Analysis Summary**",
            "weight": "Bolder",
            "spacing": "Medium"
          },
          {
            "type": "TextBlock",
            "text": "Memory usage has significantly exceeded the statistical baseline over the last 24 hours. The current memory consumption is 4.2 standard deviations above the historical average, indicating a potential memory leak or unexpected load increase.",
            "wrap": true,
            "spacing": "Small"
          },
          {
            "type": "TextBlock",
            "text": "**Recommended Actions**",
            "weight": "Bolder",
            "spacing": "Medium"
          },
          {
            "type": "TextBlock",
            "text": "1. Review application logs for memory leak indicators or exceptions\n2. Check recent deployments for code changes that may cause increased memory usage\n3. Analyze traffic patterns to determine if load increase is expected\n4. Consider scaling up if sustained high memory is required\n5. Restart container as immediate mitigation if memory leak is confirmed",
            "wrap": true,
            "spacing": "Small"
          },
          {
            "type": "TextBlock",
            "text": "**Additional Context**",
            "weight": "Bolder",
            "spacing": "Medium"
          },
          {
            "type": "FactSet",
            "facts": [
              {
                "title": "Error Rate:",
                "value": "2.3% (within normal range)"
              },
              {
                "title": "CPU Usage:",
                "value": "45% (within normal range)"
              },
              {
                "title": "Request Count:",
                "value": "43,200 requests (24h total)"
              },
              {
                "title": "Data Freshness:",
                "value": "98% (sufficient for analysis)"
              }
            ]
          }
        ],
        "actions": [
          {
            "type": "Action.OpenUrl",
            "title": "View Resource in Portal",
            "url": "https://portal.azure.com/#@${AZURE_TENANT_ID}/resource/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${OCTOPETS_RG_NAME:-rg-octopets-lab}/providers/Microsoft.App/containerApps/octopetsapi/overview"
          },
          {
            "type": "Action.OpenUrl",
            "title": "View Metrics",
            "url": "https://portal.azure.com/#blade/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/overview"
          }
        ]
      }
    }
  ]
}
EOF
)

echo "Sending sample anomaly alert..."
echo ""

# Send payload to Teams
HTTP_CODE=$(curl -s -o /tmp/teams-response.txt -w "%{http_code}" \
  -X POST "$TEAMS_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

echo "HTTP Response Code: $HTTP_CODE"
echo ""

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "202" ]; then
  echo "✅ SUCCESS: Sample anomaly alert sent to Teams!"
  echo ""
  echo "Check your Teams channel to see what a real health check alert looks like."
  echo "This demonstrates the format the SRE Agent will use when anomalies are detected."
  echo ""
  exit 0
else
  echo "❌ ERROR: Failed to send message to Teams"
  echo ""
  echo "Response:"
  cat /tmp/teams-response.txt
  echo ""
  exit 1
fi
