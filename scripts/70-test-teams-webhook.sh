#!/usr/bin/env bash
set -euo pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test Microsoft Teams Webhook Connection
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Tests the Teams webhook by sending a test message.
# Usage: ./scripts/70-test-teams-webhook.sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/load-env.sh"

# Validate required environment variables
: "${TEAMS_WEBHOOK_URL:?Missing TEAMS_WEBHOOK_URL. Please set it in .env file.}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing Teams Webhook Connection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create test payload (Adaptive Card format)
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
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
            "text": "🔔 Azure Health Check - Test Message",
            "size": "Large",
            "weight": "Bolder",
            "color": "Accent"
          },
          {
            "type": "TextBlock",
            "text": "Connection Test",
            "size": "Medium",
            "weight": "Bolder",
            "spacing": "Medium"
          },
          {
            "type": "FactSet",
            "facts": [
              {
                "title": "Status:",
                "value": "✅ Teams webhook is configured correctly"
              },
              {
                "title": "Timestamp:",
                "value": "$TIMESTAMP"
              },
              {
                "title": "Lab:",
                "value": "Azure SRE Agent Lab"
              },
              {
                "title": "Demo:",
                "value": "Health Check - Anomaly Detection"
              }
            ]
          },
          {
            "type": "TextBlock",
            "text": "If you see this message, your Teams webhook is ready to receive health check alerts from the Azure SRE Agent.",
            "wrap": true,
            "spacing": "Medium"
          }
        ]
      }
    }
  ]
}
EOF
)

echo "Sending test message to Teams channel..."
echo ""

# Send payload to Teams
HTTP_CODE=$(curl -s -o /tmp/teams-response.txt -w "%{http_code}" \
  -X POST "$TEAMS_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

echo "HTTP Response Code: $HTTP_CODE"
echo ""

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "202" ]; then
  echo "✅ SUCCESS: Test message sent to Teams!"
  echo ""
  echo "Check your Teams channel to verify the message was received."
  echo "If you see the test message, your webhook is configured correctly."
  echo ""
  echo "Response:"
  cat /tmp/teams-response.txt
  echo ""
  exit 0
else
  echo "❌ ERROR: Failed to send message to Teams"
  echo ""
  echo "Response:"
  cat /tmp/teams-response.txt
  echo ""
  echo ""
  echo "Troubleshooting:"
  echo "1. Verify TEAMS_WEBHOOK_URL in .env is correct"
  echo "2. Check that the webhook is still active in Teams"
  echo "3. Ensure the webhook hasn't been deleted or disabled"
  echo ""
  exit 1
fi
