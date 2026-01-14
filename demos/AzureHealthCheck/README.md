# Azure Health Check - Automated Anomaly Detection Demo

## Overview

This demo showcases an **autonomous Azure SRE Agent** that monitors Azure resource health, detects anomalies using statistical analysis, and sends notifications to Microsoft Teams when issues are found.

### Key Capabilities

- **Autonomous Monitoring**: Scheduled health checks every 24 hours
- **Auto-Discovery**: Automatically discovers Azure resources in scope (subscription/resource groups)
- **Multi-Metric Analysis**: Monitors CPU, memory, and error rates across different Azure resource types
- **Statistical Anomaly Detection**: Uses robust methods (MAD, z-score ≥3) instead of static thresholds
- **Smart Notifications**: Only sends Teams messages when anomalies are detected
- **Read-Only Operations**: No modifications to infrastructure, safe for production environments

### Supported Azure Resources

- **Virtual Machines**: CPU Percentage, Memory metrics
- **App Service**: CPU Percentage, Working Set memory
- **Azure Kubernetes Service (AKS)**: Node/pod CPU and memory usage
- **Container Apps**: CPU Usage, Memory usage
- **Application Insights**: Error rates, exception counts, 5xx responses

## Architecture

```
┌─────────────────────┐
│  SRE Agent          │
│  (Scheduled Trigger)│
│  Every 24h          │
└──────────┬──────────┘
           │
           │ 1. Auto-discover resources
           ▼
┌─────────────────────────────────┐
│  Azure Monitor / Log Analytics   │
│  - Collect 24h metrics           │
│  - CPU, Memory, Error rates      │
└──────────┬──────────────────────┘
           │
           │ 2. Analyze data
           ▼
┌─────────────────────────────────┐
│  Anomaly Detection Engine        │
│  - MAD / Z-score analysis        │
│  - Threshold comparison          │
└──────────┬──────────────────────┘
           │
           │ 3. If anomalies found
           ▼
┌─────────────────────────────────┐
│  Microsoft Teams                 │
│  - Webhook notification          │
│  - Resource details + metrics    │
└─────────────────────────────────┘
```

## Prerequisites

- **Azure Subscription** with resources to monitor
- **Azure SRE Agent** deployed (see main lab setup)
- **Microsoft Teams** account with access to create webhooks
- **Permissions**:
  - Reader access to Azure resources being monitored
  - Log Analytics Reader for query access
  - Teams channel admin to create incoming webhook

## Configuration Steps

### Step 1: Create Teams Webhook via Power Automate

1. **Open Microsoft Teams** and navigate to the channel where you want to receive alerts

2. **Click the three dots (...)** next to the channel name

3. **Select "Workflows"**

4. **Create a new workflow**:
   - Click "Create from blank"
   - Or search for "When a webhook request is received"

5. **Configure the workflow**:
   - **Trigger**: "When a Teams webhook request is received"
   - **Action**: "Post adaptive card in a chat or channel"
   - Set channel to your desired Teams channel
   - Set adaptive card content to: `triggerBody()?['attachments'][0]['content']`

6. **Save the workflow** and **copy the webhook URL**
   - Format: `https://[tenant].powerplatform.com/...workflows/.../triggers/manual/paths/invoke?...`

7. **Save the webhook URL** - you'll need it for configuration

> **Note**: This uses Power Automate instead of traditional Incoming Webhook to support Adaptive Card format with rich formatting.

### Step 2: Configure Webhook URL in Environment

1. **Add webhook URL to `.env` file** (use quotes to handle special characters):
   ```bash
   TEAMS_WEBHOOK_URL="https://your-powerplatform-webhook-url-here"
   ```

2. **Load the environment variables**:
   ```bash
   source scripts/load-env.sh
   ```

3. **Test the webhook connection**:
   ```bash
   ./scripts/70-test-teams-webhook.sh
   ```

   You should see:
   - ✅ SUCCESS message in terminal
   - Test message in your Teams channel

4. **Optional: Send sample anomaly alert**:
   ```bash
   ./scripts/71-send-sample-anomaly.sh
   ```

   This demonstrates what a real health check alert will look like.

### Step 3: Configure Azure SRE Agent Teams Connector

1. **Navigate to Azure Portal** → Search for your SRE Agent resource:
   ```
   Resource Group: rg-sre-agent-lab
   Resource Name: sre-agent-lab
   ```

2. **Go to "Connectors"** in the left navigation menu

3. **Click "+ Add Connector"**

4. **Select "Microsoft Teams"** from the connector types

5. **Enter connector details**:
   - **Name**: `AzureHealthAlerts`
   - **Description**: `Teams webhook for health check notifications`
   - **Webhook URL**: Paste the URL from Step 1

6. **Click "Save"**

### Step 4: Upload Subagent Configuration

1. **Open Azure Portal** → Navigate to your SRE Agent resource

2. **Click "Subagent Builder"** in the left navigation

3. **Click "+ New Subagent"**

4. **Configure subagent trigger**:
   - **Name**: `healthcheckagent`
   - **Trigger Type**: `Scheduled`
   - **Schedule** (cron expression):
     - Daily at midnight UTC: `0 0 * * *` (Recommended)
     - Every 6 hours: `0 */6 * * *`
     - Every 12 hours: `0 */12 * * *`
     - Daily at 9 AM UTC: `0 9 * * *`
   - **Mode**: `Autonomous`
   - **Task details**: 
     ```
     Monitor Azure resources (Container Apps, VMs, AKS, App Service) for anomalies. 
     Analyze 24-hour metrics (CPU, memory, errors, cost) using MAD/z-score ≥3 detection. 
     Check Azure Advisor recommendations and resource dependencies. 
     If anomalies detected: send Adaptive Card alert to Teams with root cause analysis, 
     auto-remediation suggestions, and action buttons. 
     Success: Teams message sent when anomalies found. Failure: log error in execution history. 
     Silent completion if no anomalies (normal operation).
     ```

   > **Why Scheduled?** This is a proactive monitoring agent that analyzes 24-hour windows of metrics to detect statistical anomalies, unlike reactive agents triggered by incidents.

5. **Paste YAML content**:
   - Copy the content from `azurehealthcheck-subagent-simple.yaml`
   - Paste into the YAML editor

6. **Click "Validate"** to check syntax

7. **Click "Save"**

### Step 5: Test the Configuration

#### Test 1: Verify Teams Webhook (Already Done)

If you haven't already, run:
```bash
./scripts/70-test-teams-webhook.sh
```

You should see a test message in your Teams channel.

#### Test 2: Send Sample Anomaly Alert

```bash
./scripts/71-send-sample-anomaly.sh
```

This sends a realistic anomaly alert showing what the agent will send when it detects issues.

> **Important**: Tests 1 and 2 validate your **Teams webhook + Adaptive Card formatting**.
> They do **not** prove the Azure SRE Agent connector is configured correctly.
> For end-to-end validation (agent execution → Teams connector), run Tests 3 and 4.

#### Test 3: Trigger Manual Health Check

1. **Navigate to SRE Agent** in Azure Portal

2. **Go to "Subagent Builder"** → Select `healthcheckagent`

3. **Click "Run Now"** to trigger an immediate execution

4. **Monitor execution**:
   - Check the "Execution History" tab
   - View logs for auto-discovery and metric collection
   - Verify if anomalies were detected

#### Test 4: Force a Real Anomaly (Recommended)

The easiest way to force a real anomaly in this lab is to enable one of the Octopets backend injectors
and generate traffic so Azure Monitor has measurable CPU/memory impact.

Prereqs:
- Octopets is deployed and reachable
- Your `.env` has `OCTOPETS_RG_NAME`, `OCTOPETS_API_URL`, and `OCTOPETS_FE_URL`

**Option A — CPU anomaly (fast, safe)**

```bash
./scripts/61-enable-cpu-stress.sh
./scripts/60-generate-traffic.sh 15
```

Wait ~5–15 minutes for metrics aggregation, then in Azure Portal run the `healthcheckagent` subagent again.

Cleanup:

```bash
./scripts/62-disable-cpu-stress.sh
```

**Option B — Memory anomaly (more aggressive)**

```bash
./scripts/63-enable-memory-errors.sh
./scripts/60-generate-traffic.sh 10
```

Wait ~5–15 minutes, then run the `healthcheckagent` subagent again.

Cleanup:

```bash
./scripts/64-disable-memory-errors.sh
```

> Tip: If you still see "No anomalies detected", extend traffic duration (e.g., 20–30 minutes)
> or re-run after another few minutes to allow metrics to roll up.

#### Test 5: Generate Anomalies (Manual CLI Alternative)

To test anomaly detection, you can temporarily stress an Azure resource:

```bash
# Example: Enable memory leak in Container App
az containerapp update \
  -n octopetsapi \
   -g "$OCTOPETS_RG_NAME" \
  --set-env-vars "MEMORY_ERRORS=true"

# Generate traffic to trigger memory increase
./scripts/60-generate-traffic.sh 15

# Wait 24 hours or manually trigger the agent
# After testing, disable the leak:
az containerapp update \
  -n octopetsapi \
   -g "$OCTOPETS_RG_NAME" \
  --set-env-vars "MEMORY_ERRORS=false"
```

## Expected Behavior

### When Anomalies Are Found

The agent will:
1. **Detect** resources with metrics exceeding 3x MAD or z-score ≥3
2. **Compose** a concise Teams message using **Adaptive Card format** (v1.4) with:
   - Resource name and type
   - Metric that exceeded threshold (CPU/Memory/Error rate)
   - Observed value vs. baseline
   - Timeframe (last 24 hours)
   - Suggested next steps
   - Action buttons to open Azure Portal
3. **Send** notification to configured Teams channel via Power Automate webhook
4. **Log** findings in SRE Agent execution history

Example Teams message (rendered as rich Adaptive Card):
```
⚠️ Azure Health Check Alert

Anomaly Detected
Resource health threshold exceeded

Resource:               octopetsapi (Container App)
Resource Group:         rg-octopets-lab
Metric:                 Working Set Memory
Observed Value:         95% (1.02 GB / 1.07 GB limit)
Baseline:               65% (24h average)
Threshold:              3σ exceeded (z-score: 4.2)
Timeframe:              2025-12-17 00:00 UTC → 2025-12-18 00:00 UTC
Status:                 🔴 ANOMALY DETECTED

Analysis Summary:
Memory usage has significantly exceeded the statistical baseline over 
the last 24 hours. The current memory consumption is 4.2 standard 
deviations above the historical average, indicating a potential memory 
leak or unexpected load increase.

Recommended Actions:
1. Review application logs for memory leak indicators or exceptions
2. Check recent deployments for code changes
3. Analyze traffic patterns to determine if load increase is expected
4. Consider scaling up if sustained high memory is required
5. Restart container as immediate mitigation if memory leak is confirmed

[View Resource in Portal]  [View Metrics]
```

> **Note**: Messages use Adaptive Cards with TextBlocks, FactSets, and action buttons for a rich Teams experience.

### When No Anomalies Are Found

The agent will:
1. **Analyze** all metrics across discovered resources
2. **Determine** no statistical anomalies exist
3. **Complete** execution silently (no Teams message)
4. **Log** "No anomalies detected" in execution history

## Customization

### Modify Monitoring Scope

Edit the system prompt in `azurehealthcheck-subagent-simple.yaml`:

```yaml
Scope discovery and configuration:
- Monitor specific resource group: /subscriptions/{sub-id}/resourceGroups/rg-production
- Or specific resources by tags: Environment=Production
```

### Adjust Anomaly Thresholds

Add static thresholds to the system prompt:

```yaml
Data collection:
- Use static thresholds if preferred:
  CPU: >85% sustained for 1 hour
  Memory: >90% sustained for 1 hour
  Error rate: >5% of total requests
```

### Change Schedule

Modify the trigger schedule in Azure Portal when creating/editing the subagent:

**Common Schedules** (cron format):
- **Every 6 hours**: `0 */6 * * *` - More frequent monitoring, catches issues faster
- **Every 12 hours**: `0 */12 * * *` - Balanced approach, twice daily
- **Daily at 9 AM UTC**: `0 9 * * *` - Aligns with business hours
- **Daily at midnight UTC**: `0 0 * * *` - Low overhead, full day analysis
- **Every Monday at midnight**: `0 0 * * 1` - Weekly health checks

Choose based on:
- **Criticality** of resources (more critical = more frequent)
- **Teams notification volume** tolerance
- **Azure Monitor query costs** (more frequent = higher costs)

### Add Custom Metrics

Extend the YAML to include additional metrics:

```yaml
- Network egress/ingress rates
- Database DTU/RU consumption
- Storage account throttling
- Function execution failures
```

## Metrics Reference

### Container Apps
- **CPU Usage**: `WorkingSetBytes` / Memory Limit
- **Memory**: `WorkingSetBytes` (absolute)
- **Requests**: `Requests` count
- **Errors**: `Requests` with `resultCode >= 500`

### App Service
- **CPU Percentage**: `CpuPercentage`
- **Memory**: `WorkingSet`
- **HTTP 5xx**: `Http5xx`
- **Response Time**: `HttpResponseTime`

### Virtual Machines
- **CPU**: `Percentage CPU`
- **Memory**: Guest OS metrics (requires VM Insights)
- **Disk**: `Disk Read/Write Bytes`

### AKS
- **Node CPU**: `node_cpu_usage_percentage`
- **Node Memory**: `node_memory_working_set_percentage`
- **Pod restarts**: Kusto query on `KubePodInventory`

## Troubleshooting

### Issue: No Teams messages received

**Check**:
1. Webhook URL is correct in `.env` file with proper quotes
2. Test webhook using provided scripts:
   ```bash
   ./scripts/70-test-teams-webhook.sh
   ```
3. Verify agent execution completed (check logs for "Teams message sent")
4. Ensure anomalies were actually detected (check execution summary)
5. Check Power Automate flow run history for errors

**Solution**:
```bash
# Verify .env has quoted webhook URL
grep TEAMS_WEBHOOK_URL .env

# Should show: TEAMS_WEBHOOK_URL="https://..."
# If not quoted, URLs with & characters will fail

# Test with sample anomaly
./scripts/71-send-sample-anomaly.sh
```

### Issue: Webhook returns error about Adaptive Card

**Error**: `InvalidBotAdaptiveCard` or `Property 'type' must be 'AdaptiveCard'`

**Cause**: Webhook expects Adaptive Card format, not MessageCard format

**Solution**:
- Ensure using Power Automate webhook (not traditional Incoming Webhook)
- Verify scripts use Adaptive Card v1.4 format (already implemented in test scripts)
- Check Power Automate flow action uses: `triggerBody()?['attachments'][0]['content']`

### Issue: Agent validation failed

**Check**:
- YAML syntax is valid (no tabs, proper indentation)
- All required fields present: `api_version`, `kind`, `spec`
- Tool names match available SRE Agent tools

**Solution**:
- Copy YAML from `azurehealthcheck-subagent-simple.yaml` exactly
- Use Azure Portal YAML validator before saving

### Issue: Metrics not found

**Check**:
- Resources have diagnostic settings enabled
- Log Analytics workspace is connected to resources
- Retention period includes last 24 hours
- Metrics are available for resource type (some require guest agent)

**Solution**:
```bash
# Verify metrics availability
az monitor metrics list-definitions \
  --resource /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.App/containerApps/{app}

# Check if diagnostic logs are enabled
az monitor diagnostic-settings list \
  --resource /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.App/containerApps/{app}
```

### Issue: Auto-discovery fails

**Check**:
- SRE Agent has Reader permissions on subscription/resource groups
- Azure CLI context is set correctly in agent environment
- Resources exist in the expected scope

**Solution**:
- Explicitly specify scope in system prompt
- Verify role assignments in Azure Portal → IAM

### Issue: Too many false positives

**Adjust**:
- Increase anomaly threshold from 3σ to 4σ or 5σ
- Use longer baseline period (48h or 7 days)
- Add static thresholds for known normal ranges
- Filter out specific resources by tag

## Architecture Details

### Data Flow

1. **Trigger**: Scheduled trigger fires (e.g., daily at midnight)
2. **Discovery**: Agent uses Azure CLI to discover resources in scope
3. **Collection**: Parallel queries to Azure Monitor for 24h metrics
4. **Analysis**: Statistical anomaly detection on each metric
5. **Notification**: Conditional Teams message if anomalies found
6. **Logging**: Execution results stored in SRE Agent history

### Tools Used by Agent

- `RunAzCliReadCommands`: Execute read-only Azure CLI commands
- `GetResourceDetailedProperties`: Retrieve resource configurations
- `GetResourceHealthInfo`: Check Azure Resource Health status
- `GetResourceIdForResourceName`: Resolve resource names to IDs
- `GetResourcePropertiesRealTime`: Get current resource state
- `SendTeamsMessage`: Post message to Teams webhook
- `QueryLogAnalyticsByResourceId`: Execute Kusto queries for logs/metrics

### Security Considerations

- **Read-Only**: Agent only reads metrics, no write operations
- **Scoped Access**: Limited to specific resource groups via RBAC
- **Webhook Security**: Teams webhook URLs should be kept confidential
- **No Secrets in YAML**: Webhook configured via connector, not hardcoded

## Related Documentation

- [Azure SRE Agent Overview](../../README.md)
- [ServiceNow Integration Demo](../ServiceNowAzureResourceHandler/README.md)
- [Azure Monitor Metrics](https://learn.microsoft.com/azure/azure-monitor/essentials/metrics-supported)
- [Log Analytics Queries](https://learn.microsoft.com/azure/azure-monitor/logs/log-query-overview)
- [Teams Incoming Webhooks](https://learn.microsoft.com/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook)

## Next Steps

After configuring this demo:

1. **Monitor agent execution** for 7 days to establish baseline
2. **Tune thresholds** based on false positive/negative rates
3. **Expand scope** to include additional resource types
4. **Create runbooks** for common remediation actions
5. **Integrate with incident management** (optional)

## Cleanup

To disable the health check agent:

1. **Azure Portal** → SRE Agent → Subagent Builder
2. **Select** `healthcheckagent`
3. **Disable** the scheduled trigger or **delete** the subagent
4. **Optional**: Remove Teams webhook connector

---

**Demo Version**: 1.0  
**Last Updated**: December 18, 2025  
**Region**: Sweden Central  
**SRE Agent Mode**: Autonomous
