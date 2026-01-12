#!/usr/bin/env bash
# Deploy Azure Logic App for ServiceNow integration with authentication
set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [[ -f "$REPO_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
else
  echo "ERROR: .env file not found. Run scripts/load-env.sh first." >&2
  exit 1
fi

# Validate required environment variables
: "${AZURE_SUBSCRIPTION_ID:?Missing AZURE_SUBSCRIPTION_ID in .env}"
: "${OCTOPETS_RG_NAME:?Missing OCTOPETS_RG_NAME in .env}"
: "${SERVICENOW_INSTANCE:?Missing SERVICENOW_INSTANCE in .env}"
: "${SERVICENOW_USERNAME:?Missing SERVICENOW_USERNAME in .env}"
: "${SERVICENOW_PASSWORD:?Missing SERVICENOW_PASSWORD in .env}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Deploying Logic App for ServiceNow Integration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Configuration:"
echo "  Subscription ID:      $AZURE_SUBSCRIPTION_ID"
echo "  Resource Group:       $OCTOPETS_RG_NAME"
echo "  ServiceNow Instance:  $SERVICENOW_INSTANCE.service-now.com"
echo "  ServiceNow User:      $SERVICENOW_USERNAME"
echo ""

# Check if logged in to Azure
if ! az account show >/dev/null 2>&1; then
  echo "ERROR: Not logged in to Azure. Run scripts/20-az-login.sh first." >&2
  exit 1
fi

# Set active subscription
echo "Setting active subscription..."
az account set --subscription "$AZURE_SUBSCRIPTION_ID"

# Deploy Logic App
BICEP_FILE="$REPO_ROOT/demos/ServiceNowAzureResourceHandler/servicenow-logic-app.bicep"

if [[ ! -f "$BICEP_FILE" ]]; then
  echo "ERROR: Bicep template not found at $BICEP_FILE" >&2
  exit 1
fi

DEPLOYMENT_NAME="servicenow-logicapp-$(date +%Y%m%d-%H%M%S)"

echo "Deploying Logic App..."
echo "  Template: $BICEP_FILE"
echo "  Deployment: $DEPLOYMENT_NAME"
echo ""

DEPLOYMENT_OUTPUT=$(az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$OCTOPETS_RG_NAME" \
  --template-file "$BICEP_FILE" \
  --parameters \
    subscriptionId="$AZURE_SUBSCRIPTION_ID" \
    resourceGroupName="$OCTOPETS_RG_NAME" \
    serviceNowInstance="$SERVICENOW_INSTANCE" \
    serviceNowUsername="$SERVICENOW_USERNAME" \
    serviceNowPassword="$SERVICENOW_PASSWORD" \
  --query 'properties.outputs' \
  -o json)

if [[ $? -eq 0 ]]; then
  echo "✓ Logic App deployed successfully"
  echo ""
  
  # Extract outputs
  LOGIC_APP_CALLBACK_URL=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.logicAppCallbackUrl.value')
  LOGIC_APP_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.logicAppName.value')
  
  echo "Logic App Details:"
  echo "  Name: $LOGIC_APP_NAME"
  echo "  Callback URL: ${LOGIC_APP_CALLBACK_URL:0:80}..."
  echo ""
  
  # Update .env with webhook URL
  "$SCRIPT_DIR/set-dotenv-value.sh" "SERVICENOW_WEBHOOK_URL" "$LOGIC_APP_CALLBACK_URL"
  
  echo "✓ Updated .env with SERVICENOW_WEBHOOK_URL"
  echo ""
  
  # Test the Logic App
  echo "Testing Logic App..."
  TEST_PAYLOAD='{
    "schemaId": "azureMonitorCommonAlertSchema",
    "data": {
      "essentials": {
        "alertRule": "Test Alert from deployment script",
        "severity": "Sev2",
        "monitorCondition": "Fired",
        "description": "This is a test alert to verify Logic App configuration",
        "firedDateTime": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"
      },
      "alertContext": {}
    }
  }'
  
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -d "$TEST_PAYLOAD" \
    "$LOGIC_APP_CALLBACK_URL")
  
  if [[ "$HTTP_STATUS" -eq 200 ]] || [[ "$HTTP_STATUS" -eq 202 ]]; then
    echo "✓ Logic App test successful (HTTP $HTTP_STATUS)"
    echo ""
    echo "Check ServiceNow for test incident:"
    echo "  https://$SERVICENOW_INSTANCE.service-now.com/now/nav/ui/classic/params/target/incident_list.do"
  else
    echo "WARNING: Logic App test returned HTTP $HTTP_STATUS" >&2
    echo "  Check Logic App run history in Azure Portal" >&2
  fi
  echo ""
  
else
  echo "ERROR: Logic App deployment failed" >&2
  exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Next Steps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Re-deploy alert rules with new webhook URL:"
echo "   scripts/50-deploy-alert-rules.sh"
echo ""
echo "2. Generate traffic to trigger alerts:"
echo "   scripts/60-generate-traffic.sh 10"
echo ""
echo "3. Monitor Logic App runs:"
echo "   az logic workflow show -n $LOGIC_APP_NAME -g $OCTOPETS_RG_NAME --query 'id' -o tsv"
echo "   # Then visit in Azure Portal: Logic App > Overview > Runs history"
echo ""
