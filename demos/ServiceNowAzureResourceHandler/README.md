# ServiceNow Incident Automation Demo

This demo showcases how Azure SRE Agent automatically investigates and resolves incidents created in ServiceNow when Azure Monitor detects issues with the Octopets application.

## Overview

**Demo Scenario**: Memory leak in Octopets backend API triggers automated incident response workflow:

1. **Detection**: Azure Monitor detects high memory usage (>80%)
2. **Incident Creation**: ServiceNow incident automatically created via webhook
3. **Investigation**: Azure SRE Agent investigates via ServiceNow subagent
4. **Analysis**: SRE Agent queries Log Analytics and metrics
5. **GitHub Issue**: Detailed analysis posted as GitHub issue
6. **Resolution**: ServiceNow incident updated with findings
7. **Notification**: Email sent to stakeholders

**Expected Duration**: 5-15 minutes end-to-end

## Prerequisites

### 1. ServiceNow Developer Instance

Sign up for a free developer instance:
- Visit: https://developer.servicenow.com/dev.do
- Create account and request instance
- Note your instance URL (e.g., `https://dev12345.service-now.com`)
- Extract instance prefix: `dev12345`

### 2. Azure Resources (Already Deployed)

Verify these resources exist:
```bash
# Check Octopets resources
az containerapp list -g rg-octopets-lab -o table

# Check SRE Agent
az resource show --name sre-agent-lab --resource-group rg-sre-agent-lab
```

Expected output:
- Backend Container App: `octopetsapi`
- Frontend Container App: `octopetsfe`
- SRE Agent: `sre-agent-lab` (High RBAC access)

### 3. Environment Configuration

Add ServiceNow credentials to `.env`:
```bash
# Load environment
source scripts/load-env.sh

# Add ServiceNow configuration
scripts/set-dotenv-value.sh "SERVICENOW_INSTANCE" "dev12345"  # Your instance
scripts/set-dotenv-value.sh "SERVICENOW_USERNAME" "admin"
scripts/set-dotenv-value.sh "SERVICENOW_PASSWORD" "your-password"
scripts/set-dotenv-value.sh "INCIDENT_NOTIFICATION_EMAIL" "your-email@example.com"
```

## Deployment Steps

### Step 1: Deploy Azure Monitor Alert Rules

```bash
# Load environment
source scripts/load-env.sh

# Deploy alert rules and ServiceNow action group
scripts/50-deploy-alert-rules.sh
```

**Expected Output**:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Deploying Azure Monitor Alert Rules and ServiceNow Integration
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Configuration:
  Subscription ID:      <your-subscription-id>
  Resource Group:       rg-octopets-lab
  ServiceNow Instance:  dev12345.service-now.com
  ServiceNow User:      admin

✓ ServiceNow connection successful (HTTP 200)
✓ Deployment successful: octopets-alerts-20251217-123456

Action Group:
  Name: ServiceNow-ActionGroup
  Webhook: https://dev12345.service-now.com/api/now/table/incident

Alert Rules:
  - High Memory Usage - Octopets API
  - Very High Memory Usage - Octopets API
  - High Error Rate - Octopets API
  - Critical Error Rate - Octopets API
```

**What Was Deployed**:
- 4 metric alert rules (memory + error rate)
- 1 action group (ServiceNow webhook)
- Auto-mitigation enabled on all alerts

### Step 2: Configure SRE Agent Subagent

1. **Open Azure Portal**:
   ```bash
   # Get SRE Agent URL
   echo "https://portal.azure.com/#@$AZURE_TENANT_ID/resource/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/rg-sre-agent-lab/providers/Microsoft.SreAgent/sreAgents/sre-agent-lab"
   ```

2. **Navigate to Subagent Builder**:
   - Azure Portal → `rg-sre-agent-lab` → `sre-agent-lab`
   - Left menu → **Subagent Builder**
   - Click **Create new trigger** or **Edit existing**

3. **Configure ServiceNow Trigger**:
   - **Trigger Name**: `ServiceNow Incident`
   - **Trigger Type**: `Scheduled` (every 2 minutes)
   - **YAML Configuration**: Copy contents from `demo/servicenow-subagent-simple.yaml`
   - **Update Email**: Replace `<INSERT_YOUR_EMAIL_HERE>` with your actual email in the system_prompt
   - **Save and Enable**

4. **Verify Connectors**:
   - Left menu → **Connectors**
   - Ensure these are configured:
     - ✓ ServiceNow (REST API with instance URL)
     - ✓ GitHub (for issue creation)
     - ✓ Outlook (for email notifications)

### Step 3: Verify Configuration

```bash
# Check alert rules
az monitor metrics alert list -g rg-octopets-lab \
  --query '[].{Name:name, Enabled:enabled, Severity:severity}' \
  -o table

# Check action group
az monitor action-group list -g rg-octopets-lab -o table

# Test ServiceNow connection manually
curl -X GET \
  -H "Accept: application/json" \
  -u "$SERVICENOW_USERNAME:$SERVICENOW_PASSWORD" \
  "https://$SERVICENOW_INSTANCE.service-now.com/api/now/table/incident?sysparm_limit=1"
```

**Expected Results**:
- 4 alert rules shown as `Enabled: true`
- Action group `ServiceNow-ActionGroup` exists
- ServiceNow API returns `HTTP 200` with JSON response

## Running the Demo

### Trigger Memory Leak

```bash
# Load environment
source scripts/load-env.sh

# Enable memory leak feature flag
az containerapp update \
  -n octopetsapi \
  -g rg-octopets-lab \
  --set-env-vars "MEMORY_ERRORS=true"

# Wait for container restart (30-60 seconds)
echo "Waiting for container to restart..."
sleep 60

# Verify restart
az containerapp replica list \
  -n octopetsapi \
  -g rg-octopets-lab \
  --query '[].name' \
  -o table
```

### Generate Memory Leak Traffic

1. **Open Octopets Frontend**:
   ```bash
   echo "Frontend URL: $OCTOPETS_FE_URL"
   # Open in browser
   ```

2. **Trigger Memory Leak**:
   - Click on any product (e.g., "Octopus Plush")
   - Click **"View Details"** button
   - **Repeat 5-10 times** (each click loads images without cleanup)
   - Memory usage will climb with each click

3. **Monitor Progress**:
   ```bash
   # Watch memory usage (run in separate terminal)
   while true; do
     az monitor metrics list \
       --resource /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/rg-octopets-lab/providers/Microsoft.App/containerApps/octopetsapi \
       --metric WorkingSetBytes \
       --interval PT1M \
       --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
       --query 'value[0].timeseries[0].data[-1].average' \
       -o tsv | awk '{printf "Memory: %.2f MB\n", $1/1024/1024}'
     sleep 30
   done
   ```

### Expected Workflow Timeline

| Time | Event | What Happens |
|------|-------|--------------|
| T+0 min | Trigger leak | Click "View Details" 5-10 times on frontend |
| T+2 min | Memory climbs | Memory usage crosses 80% threshold |
| T+5 min | Alert fires | Azure Monitor evaluates 5-minute window |
| T+5 min | ServiceNow incident | Webhook creates incident (Priority: High) |
| T+6 min | SRE Agent polls | Agent detects new incident via API query |
| T+7 min | Log query | Agent queries Log Analytics for errors |
| T+8 min | Metric analysis | Agent retrieves memory and CPU metrics |
| T+10 min | GitHub issue | Agent creates issue with detailed analysis |
| T+12 min | ServiceNow update | Agent updates incident with resolution |
| T+15 min | Email sent | Stakeholders notified via Outlook |

## Verification Steps

### 1. Check Alert Fired

```bash
# List recent alert activations
az monitor metrics alert show \
  -n "High Memory Usage - Octopets API" \
  -g rg-octopets-lab \
  --query '{Name:name, Enabled:enabled, LastFired:lastUpdatedTime}' \
  -o json

# View alert history
az monitor activity-log list \
  --resource-group rg-octopets-lab \
  --start-time "$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --query "[?contains(operationName.value, 'Microsoft.Insights/metricAlerts')].{Time:eventTimestamp, Alert:resourceId, Status:status.value}" \
  -o table
```

### 2. Check ServiceNow Incident

**Option A: ServiceNow UI**:
1. Login to ServiceNow: `https://$SERVICENOW_INSTANCE.service-now.com`
2. Navigate to: **Incident** → **Open**
3. Filter by: **Priority = High**
4. Look for: "Octopets API - High Memory Usage Alert"

**Option B: REST API**:
```bash
curl -X GET \
  -H "Accept: application/json" \
  -u "$SERVICENOW_USERNAME:$SERVICENOW_PASSWORD" \
  "https://$SERVICENOW_INSTANCE.service-now.com/api/now/table/incident?sysparm_query=priority=1^ORpriority=2^short_descriptionLIKEOctopets&sysparm_fields=number,short_description,state,sys_created_on" \
  | jq '.result[] | {number, short_description, state, created: .sys_created_on}'
```

**Expected Incident Fields**:
- **Number**: INC0010001 (auto-incremented)
- **Short Description**: "Octopets API - High Memory Usage Alert"
- **Priority**: 2 - High
- **State**: Initially "1 - New", then "6 - Resolved"
- **Work Notes**: Investigation results from SRE Agent
- **Resolution Notes**: GitHub issue link

### 3. Check SRE Agent Logs

**Azure Portal**:
1. Navigate to: `rg-sre-agent-lab` → `sre-agent-lab`
2. Left menu → **Logs**
3. Run KQL query:
   ```kql
   ContainerAppConsoleLogs_CL
   | where TimeGenerated > ago(1h)
   | where Log_s contains "ServiceNow" or Log_s contains "incident"
   | project TimeGenerated, Log_s
   | order by TimeGenerated desc
   ```

**Expected Logs**:
- "Polling ServiceNow for new incidents..."
- "Found incident: INC0010001"
- "Querying Log Analytics for errors..."
- "Creating GitHub issue..."
- "Updating ServiceNow incident..."

### 4. Check GitHub Issue

```bash
# Get repository URL
echo "GitHub Repository: https://github.com/<your-org>/<your-repo>/issues"
```

**Expected Issue Content**:
- **Title**: "Memory Leak Detected in Octopets API"
- **Body**:
  - ServiceNow incident number and link
  - Log analysis with error patterns
  - Memory metrics (current usage, threshold)
  - Root cause explanation
  - Recommended actions
  - KQL queries used

### 5. Check Email Notification

**Search Inbox**:
- **Subject**: "ServiceNow Incident INC0010001 - Octopets API Memory Leak"
- **From**: Azure SRE Agent (via managed identity)
- **Contains**:
  - Incident summary
  - Investigation results
  - GitHub issue link
  - ServiceNow incident link
  - Recommended actions

## Cleanup

### Stop Memory Leak

```bash
# Disable MEMORY_ERRORS flag
az containerapp update \
  -n octopetsapi \
  -g rg-octopets-lab \
  --set-env-vars "MEMORY_ERRORS=false"

# Restart to clear memory
az containerapp update \
  -n octopetsapi \
  -g rg-octopets-lab \
  --query 'properties.provisioningState'

echo "Memory leak disabled. Container restarting..."
```

### Delete Alert Rules (Optional)

```bash
# Delete all alert rules
az monitor metrics alert delete -n "High Memory Usage - Octopets API" -g rg-octopets-lab
az monitor metrics alert delete -n "Very High Memory Usage - Octopets API" -g rg-octopets-lab
az monitor metrics alert delete -n "High Error Rate - Octopets API" -g rg-octopets-lab
az monitor metrics alert delete -n "Critical Error Rate - Octopets API" -g rg-octopets-lab

# Delete action group
az monitor action-group delete -n "ServiceNow-ActionGroup" -g rg-octopets-lab
```

### Archive ServiceNow Incidents

**ServiceNow UI**:
1. Login to ServiceNow
2. Navigate to: **Incident** → **All**
3. Select incidents with "Octopets" in description
4. Actions → **Delete** or **Archive**

## Troubleshooting

### Alert Not Firing

**Symptoms**: No ServiceNow incident created after triggering memory leak

**Checks**:
```bash
# 1. Verify memory actually increased
az monitor metrics list \
  --resource /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/rg-octopets-lab/providers/Microsoft.App/containerApps/octopetsapi \
  --metric WorkingSetBytes \
  --interval PT1M \
  --start-time "$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --query 'value[0].timeseries[0].data[].{time:timeStamp, memory:average}' \
  -o table

# 2. Check if alert rule is enabled
az monitor metrics alert show \
  -n "High Memory Usage - Octopets API" \
  -g rg-octopets-lab \
  --query 'enabled'

# 3. Check alert evaluation frequency
az monitor metrics alert show \
  -n "High Memory Usage - Octopets API" \
  -g rg-octopets-lab \
  --query '{Enabled:enabled, Frequency:evaluationFrequency, Window:windowSize, Threshold:criteria.allOf[0].threshold}'
```

**Solutions**:
- Trigger more memory leak traffic (click "View Details" 10+ times)
- Wait for full 5-minute evaluation window
- Verify MEMORY_ERRORS=true environment variable is set

### ServiceNow Incident Not Created

**Symptoms**: Alert fires but no incident appears in ServiceNow

**Checks**:
```bash
# 1. Test webhook manually
curl -v -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -u "$SERVICENOW_USERNAME:$SERVICENOW_PASSWORD" \
  -d '{"short_description":"Test Alert from Azure CLI","description":"Manual test of webhook integration","priority":"2","category":"Software"}' \
  "https://$SERVICENOW_INSTANCE.service-now.com/api/now/table/incident"

# 2. Check action group configuration
az monitor action-group show \
  -n "ServiceNow-ActionGroup" \
  -g rg-octopets-lab \
  --query 'webhookReceivers[0].serviceUri'

# 3. Check alert history
az monitor activity-log list \
  --resource-group rg-octopets-lab \
  --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --query "[?contains(operationName.value, 'Alert')].{Time:eventTimestamp, Operation:operationName.value, Status:status.value}" \
  -o table
```

**Solutions**:
- Verify ServiceNow credentials are correct
- Check ServiceNow instance is active (developer instances hibernate after inactivity)
- Verify webhook URL format: `https://[instance].service-now.com/api/now/table/incident`

### SRE Agent Not Processing Incident

**Symptoms**: ServiceNow incident created but not updated by SRE Agent

**Checks**:
```bash
# 1. Verify SRE Agent is running
az resource show \
  --name sre-agent-lab \
  --resource-group rg-sre-agent-lab \
  --query 'properties.provisioningState'

# 2. Check SRE Agent logs (Azure Portal)
# Navigate to: rg-sre-agent-lab → sre-agent-lab → Logs
# Run KQL query:
# ContainerAppConsoleLogs_CL
# | where TimeGenerated > ago(1h)
# | project TimeGenerated, Log_s
# | order by TimeGenerated desc

# 3. Verify subagent is enabled
# Azure Portal → SRE Agent → Subagent Builder → Check "ServiceNow Incident" enabled
```

**Solutions**:
- Enable ServiceNow subagent in Azure Portal
- Verify YAML configuration has no syntax errors
- Check ServiceNow connector credentials in SRE Agent
- Verify SRE Agent has RBAC permissions on rg-octopets-lab

### GitHub Issue Not Created

**Symptoms**: ServiceNow updated but no GitHub issue

**Checks**:
- Azure Portal → SRE Agent → **Connectors** → Verify **GitHub** connector configured
- Check SRE Agent has GitHub repository access (OAuth or PAT)
- Verify repository name in subagent YAML matches actual repository

**Solutions**:
- Reconfigure GitHub connector with valid credentials
- Grant SRE Agent managed identity access to GitHub repository
- Check GitHub rate limits (60 requests/hour for unauthenticated)

### Email Not Received

**Symptoms**: Everything else works but no email notification

**Checks**:
- Azure Portal → SRE Agent → **Connectors** → Verify **Outlook** connector configured
- Check email address in subagent YAML (search for `<INSERT_YOUR_EMAIL_HERE>`)
- Verify spam/junk folder
- Check Microsoft Graph API permissions for managed identity

**Solutions**:
- Update email address in subagent YAML (remove placeholder)
- Grant `Mail.Send` permission to SRE Agent managed identity
- Check Outlook connector authentication status

## Expected Costs

### Single Demo Run
- **Alert evaluations**: Free (first 10 metric alerts)
- **Log Analytics queries**: ~0.01 GB ingestion = $0.02
- **Container App uptime**: ~$0.05 for 30 minutes
- **Total**: **< $0.10 per demo run**

### Daily Testing (10 runs)
- **Estimated**: **< $1.00/day**

### Monthly Lab Environment
- **Container Apps**: ~$30-50/month (2 apps, minimal scale)
- **Log Analytics**: ~$10-20/month (minimal retention)
- **SRE Agent**: Preview pricing TBD
- **Total**: **~$50-100/month**

## Next Steps

### Explore Advanced Scenarios

1. **Auto-Remediation**: Configure SRE Agent to automatically restart containers
2. **Multi-Resource Alerts**: Add database, cache, storage alerts
3. **Custom Metrics**: Create alerts on application-specific metrics
4. **Incident Escalation**: Chain multiple ServiceNow workflows

### Production Considerations

1. **Security**: Replace basic auth with OAuth or API keys
2. **Rate Limiting**: Implement throttling for webhook calls
3. **High Availability**: Configure SRE Agent failover
4. **Compliance**: Enable audit logging for all actions
5. **RBAC**: Scope SRE Agent to minimum required permissions (Review mode first)

## References

- **Specification**: [specs/IncidentAutomationServiceNow.md](../specs/IncidentAutomationServiceNow.md)
- **Subagent YAML**: [servicenow-azure-resource-error-handler.yaml](servicenow-azure-resource-error-handler.yaml)
- **Alert Rules**: [octopets-service-now-alerts.bicep](octopets-service-now-alerts.bicep)
- **Azure SRE Agent Docs**: https://github.com/microsoft/sre-agent
- **ServiceNow REST API**: https://docs.servicenow.com/bundle/vancouver-api-reference/page/integrate/inbound-rest/concept/c_RESTAPI.html
- **Azure Monitor Alerts**: https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-overview
