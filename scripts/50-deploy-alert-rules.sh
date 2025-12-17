#!/usr/bin/env bash
# Deploy Azure Monitor alert rules and ServiceNow action group for Octopets demo
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
: "${SERVICENOW_INSTANCE:?Missing SERVICENOW_INSTANCE in .env - Add your ServiceNow instance name}"
: "${SERVICENOW_USERNAME:?Missing SERVICENOW_USERNAME in .env - Add your ServiceNow username}"
: "${SERVICENOW_PASSWORD:?Missing SERVICENOW_PASSWORD in .env - Add your ServiceNow password}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Deploying Azure Monitor Alert Rules and ServiceNow Integration"
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

# Discover Container App names
echo "Discovering Container Apps in $OCTOPETS_RG_NAME..."
BACKEND_APP_NAME=$(az containerapp list -g "$OCTOPETS_RG_NAME" --query "[?contains(name, 'api')].name" -o tsv)
FRONTEND_APP_NAME=$(az containerapp list -g "$OCTOPETS_RG_NAME" --query "[?contains(name, 'fe')].name" -o tsv)

if [[ -z "$BACKEND_APP_NAME" ]]; then
  echo "ERROR: Backend Container App not found in $OCTOPETS_RG_NAME" >&2
  exit 1
fi

if [[ -z "$FRONTEND_APP_NAME" ]]; then
  echo "ERROR: Frontend Container App not found in $OCTOPETS_RG_NAME" >&2
  exit 1
fi

echo "  Backend App:  $BACKEND_APP_NAME"
echo "  Frontend App: $FRONTEND_APP_NAME"
echo ""

# Construct ServiceNow webhook URL for incident creation
SERVICENOW_BASE_URL="https://${SERVICENOW_INSTANCE}.service-now.com"
SERVICENOW_WEBHOOK_URL="${SERVICENOW_BASE_URL}/api/now/table/incident"

# Encode credentials for webhook (Basic Auth)
# Note: In production, use OAuth or API keys instead of basic auth
SERVICENOW_AUTH_HEADER="Authorization: Basic $(echo -n "${SERVICENOW_USERNAME}:${SERVICENOW_PASSWORD}" | base64)"

echo "ServiceNow Configuration:"
echo "  Webhook URL: $SERVICENOW_WEBHOOK_URL"
echo "  Auth Method: Basic Authentication"
echo ""

# Test ServiceNow connection
echo "Testing ServiceNow connection..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Accept: application/json" \
  -H "$SERVICENOW_AUTH_HEADER" \
  "${SERVICENOW_WEBHOOK_URL}?sysparm_limit=1")

if [[ "$HTTP_STATUS" -eq 200 ]]; then
  echo "✓ ServiceNow connection successful (HTTP $HTTP_STATUS)"
else
  echo "WARNING: ServiceNow connection returned HTTP $HTTP_STATUS" >&2
  echo "  Continuing with deployment, but verify credentials are correct." >&2
fi
echo ""

# Deploy Bicep template
BICEP_FILE="$REPO_ROOT/demo/octopets-alert-rules.bicep"

if [[ ! -f "$BICEP_FILE" ]]; then
  echo "ERROR: Bicep template not found at $BICEP_FILE" >&2
  exit 1
fi

echo "Deploying alert rules using Bicep template..."
DEPLOYMENT_NAME="octopets-alerts-$(date +%Y%m%d-%H%M%S)"

DEPLOYMENT_OUTPUT=$(az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$OCTOPETS_RG_NAME" \
  --template-file "$BICEP_FILE" \
  --parameters \
    subscriptionId="$AZURE_SUBSCRIPTION_ID" \
    resourceGroupName="$OCTOPETS_RG_NAME" \
    backendAppName="$BACKEND_APP_NAME" \
    frontendAppName="$FRONTEND_APP_NAME" \
    serviceNowInstanceUrl="${SERVICENOW_INSTANCE}.service-now.com" \
    serviceNowWebhookUrl="$SERVICENOW_WEBHOOK_URL" \
  --output json)

if [[ $? -eq 0 ]]; then
  echo "✓ Deployment successful: $DEPLOYMENT_NAME"
else
  echo "ERROR: Deployment failed" >&2
  exit 1
fi
echo ""

# Extract outputs
ACTION_GROUP_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.actionGroupName.value')
ALERT_RULE_NAMES=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.alertRuleNames.value[]')

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Deployment Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Action Group:"
echo "  Name: $ACTION_GROUP_NAME"
echo "  Webhook: $SERVICENOW_WEBHOOK_URL"
echo ""
echo "Alert Rules:"
while IFS= read -r alert_name; do
  echo "  - $alert_name"
done <<< "$ALERT_RULE_NAMES"
echo ""

# Update .env with webhook URL
"$SCRIPT_DIR/set-dotenv-value.sh" "SERVICENOW_WEBHOOK_URL" "$SERVICENOW_WEBHOOK_URL"
echo "✓ Updated .env with SERVICENOW_WEBHOOK_URL"
echo ""

# Verification commands
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "To verify alert rules:"
echo "  az monitor metrics alert list -g $OCTOPETS_RG_NAME --query '[].{Name:name, Enabled:enabled, Severity:severity}' -o table"
echo ""
echo "To verify action group:"
echo "  az monitor action-group show -n $ACTION_GROUP_NAME -g $OCTOPETS_RG_NAME"
echo ""
echo "To test ServiceNow incident creation manually:"
echo "  curl -X POST \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -H '$SERVICENOW_AUTH_HEADER' \\"
echo "    -d '{\"short_description\":\"Test Alert\",\"description\":\"Test from Azure CLI\",\"priority\":\"2\"}' \\"
echo "    '$SERVICENOW_WEBHOOK_URL'"
echo ""
echo "Next Steps:"
echo "  1. Configure SRE Agent subagent in Azure Portal"
echo "  2. Paste YAML from: demo/servicenow-azure-resource-error-handler.yaml"
echo "  3. Update email address placeholder in YAML"
echo "  4. Enable the subagent"
echo "  5. Run demo: see demo/README.md for instructions"
echo ""
