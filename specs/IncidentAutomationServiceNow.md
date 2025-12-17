# ServiceNow Incident Automation Demo Specification

## Overview

This specification defines an end-to-end incident automation demo that integrates Azure SRE Agent with ServiceNow for automated incident management. The demo showcases how Azure Monitor alerts can trigger ServiceNow incidents, which are then automatically investigated and remediated by Azure SRE Agent.

### Demo Scenario: Octopets Memory Leak

The demo simulates a memory leak in the Octopets backend API that triggers automated incident response:

1. **Detection**: Azure Monitor detects high memory usage or error rate
2. **Incident Creation**: ServiceNow incident automatically created via webhook
3. **Investigation**: Azure SRE Agent investigates via ServiceNow subagent
4. **Remediation**: SRE Agent creates GitHub issue with root cause analysis
5. **Resolution**: ServiceNow incident updated with resolution details
6. **Notification**: Email notifications sent throughout the workflow

## Architecture

### Component Diagram

```
Azure Monitor Alerts
       ↓ (webhook)
ServiceNow Incident
       ↓ (API polling)
Azure SRE Agent (Subagent)
       ↓ (investigation)
Azure Resources (Log Analytics, Container Apps)
       ↓ (remediation)
GitHub Issues + ServiceNow Update
       ↓ (notification)
Outlook Email
```

### Integration Points

1. **Azure Monitor → ServiceNow**: HTTP webhook to ServiceNow REST API
2. **ServiceNow → SRE Agent**: Agent polls ServiceNow for new high-priority incidents
3. **SRE Agent → Azure**: Queries Log Analytics, Container App metrics
4. **SRE Agent → GitHub**: Creates issue with incident analysis
5. **SRE Agent → ServiceNow**: Updates incident with resolution notes
6. **SRE Agent → Outlook**: Sends email notifications

## Prerequisites

### ServiceNow Configuration

1. **Developer Instance**: Sign up at https://developer.servicenow.com/
2. **Instance URL**: Format `https://dev12345.service-now.com`
3. **Credentials**: Admin username and password
4. **REST API**: Enabled by default on developer instances
5. **Incident Table**: `incident` table accessible

### Azure Resources (Already Deployed)

- **Resource Group**: `rg-octopets-lab`
- **Container Apps**: `octopetsapi`, `octopetsfe`
- **Log Analytics**: Workspace with Container App logs
- **Application Insights**: Connected to Container Apps
- **SRE Agent**: `rg-sre-agent-lab` with High RBAC access

### Required Tools

- Azure CLI 2.74.0+
- Bash shell (dev container included)
- ServiceNow developer account
- GitHub repository access

## Configuration Files

### 1. ServiceNow Subagent YAML

**File**: `demo/servicenow-azure-resource-error-handler.yaml`

**Purpose**: Defines the SRE Agent subagent that monitors ServiceNow for incidents and automates investigation/remediation.

**Key Sections**:
- **System Prompt**: ServiceNow incident investigation specialist role
- **Workflow**: Poll incidents → Analyze logs → Create GitHub issue → Update ServiceNow
- **Connectors**: ServiceNow REST API, GitHub, Outlook

### 2. Azure Monitor Alert Rules

**File**: `demo/octopets-alert-rules.bicep`

**Purpose**: Bicep template deploying 4 metric alerts and a ServiceNow action group.

**Alerts**:
1. **High Memory Usage**: Memory > 80% for 5 minutes
2. **Very High Memory Usage**: Memory > 90% for 3 minutes
3. **High Error Rate**: >10 errors/minute for 5 minutes
4. **Critical Error Rate**: >50 errors/minute for 3 minutes

**Action Group**: HTTP webhook to ServiceNow incident creation endpoint

### 3. Deployment Script

**File**: `scripts/50-deploy-alert-rules.sh`

**Purpose**: Automates deployment of alert rules and action group.

**Operations**:
- Validates environment variables
- Discovers Container App resource IDs
- Deploys Bicep template
- Outputs alert rule names and webhook URL

### 4. Demo Execution Guide

**File**: `demo/README.md`

**Purpose**: Step-by-step instructions for running the demo.

**Sections**:
- Prerequisites checklist
- ServiceNow setup
- Alert deployment
- SRE Agent configuration
- Demo execution steps
- Verification procedures

## Environment Variables

### Required New Variables (add to `.env`)

```bash
# ServiceNow Configuration
SERVICENOW_INSTANCE="dev12345"  # Your instance prefix (without .service-now.com)
SERVICENOW_USERNAME="admin"     # ServiceNow admin username
SERVICENOW_PASSWORD="<password>" # ServiceNow admin password
SERVICENOW_WEBHOOK_URL=""       # Auto-generated after alert deployment

# Notification
INCIDENT_NOTIFICATION_EMAIL="your-email@example.com"
```

### Existing Variables (already in `.env`)

- `OCTOPETS_RG_NAME`: rg-octopets-lab
- `OCTOPETS_API_URL`: Backend Container App URL
- `AZURE_SUBSCRIPTION_ID`: Subscription ID
- `AZURE_LOCATION`: swedencentral

## Deployment Steps

### Step 1: Configure ServiceNow

```bash
# 1. Sign up for ServiceNow developer instance
# Visit: https://developer.servicenow.com/dev.do

# 2. Note your instance URL (e.g., https://dev12345.service-now.com)
# Extract the instance prefix: dev12345

# 3. Add credentials to .env
scripts/set-dotenv-value.sh "SERVICENOW_INSTANCE" "dev12345"
scripts/set-dotenv-value.sh "SERVICENOW_USERNAME" "admin"
scripts/set-dotenv-value.sh "SERVICENOW_PASSWORD" "your-password"
scripts/set-dotenv-value.sh "INCIDENT_NOTIFICATION_EMAIL" "your-email@example.com"
```

### Step 2: Deploy Alert Rules

```bash
# Load environment
source scripts/load-env.sh

# Deploy alerts and action group
scripts/50-deploy-alert-rules.sh

# Expected output:
# - 4 alert rules created
# - Action group created with ServiceNow webhook
# - SERVICENOW_WEBHOOK_URL added to .env
```

### Step 3: Configure SRE Agent Subagent

```bash
# 1. Open Azure Portal
# 2. Navigate to: rg-sre-agent-lab → sre-agent-lab
# 3. Go to: Subagent Builder
# 4. Create new trigger: "ServiceNow Incident"
# 5. Paste contents from: demo/servicenow-azure-resource-error-handler.yaml
# 6. Update email placeholder: <INSERT_YOUR_EMAIL_HERE>
# 7. Save and enable the subagent
```

### Step 4: Verify Configuration

```bash
# Check alert rules
az monitor metrics alert list -g rg-octopets-lab

# Check action group
az monitor action-group list -g rg-octopets-lab

# Verify ServiceNow connection (manual)
# Login to ServiceNow → Incident → Create Test Incident
```

## Demo Execution

### Triggering the Memory Leak

```bash
# Enable memory leak in backend
az containerapp update \
  -n octopetsapi \
  -g rg-octopets-lab \
  --set-env-vars "ERRORS=true"

# Wait for restart (30-60 seconds)
az containerapp replica list -n octopetsapi -g rg-octopets-lab

# Trigger memory leak via frontend
# 1. Open: $OCTOPETS_FE_URL
# 2. Click "View Details" on any product 5+ times
# 3. Each click loads images without cleanup
```

### Expected Workflow (5-15 minutes)

1. **T+0 minutes**: Memory leak triggered via frontend
2. **T+2 minutes**: Memory usage crosses 80% threshold
3. **T+5 minutes**: Azure Monitor alert fires
4. **T+5 minutes**: ServiceNow incident created (Priority: High)
5. **T+6 minutes**: SRE Agent polls ServiceNow, detects new incident
6. **T+7 minutes**: SRE Agent queries Log Analytics for errors
7. **T+8 minutes**: SRE Agent analyzes memory metrics
8. **T+10 minutes**: SRE Agent creates GitHub issue with analysis
9. **T+12 minutes**: SRE Agent updates ServiceNow with resolution
10. **T+15 minutes**: Email notifications sent (incident update)

### Verification Steps

```bash
# 1. Check alert fired
az monitor metrics alert show \
  -n "High Memory Usage - Octopets API" \
  -g rg-octopets-lab \
  --query "condition.allOf[0].timeAggregation"

# 2. Check ServiceNow incident
# Login to ServiceNow → Incident → Filter by Priority: High

# 3. Check SRE Agent logs
# Azure Portal → rg-sre-agent-lab → sre-agent-lab → Logs

# 4. Check GitHub issue
# GitHub → Issues → Check for new issue with "Memory Leak" title

# 5. Check email notifications
# Inbox → Search for "ServiceNow Incident"
```

## Expected Outputs

### ServiceNow Incident

**Created Fields**:
- **Number**: INC0010001 (auto-incremented)
- **Short Description**: "Octopets API - High Memory Usage Alert"
- **Priority**: 2 - High
- **Category**: Software
- **Caller**: Azure Monitor
- **Assignment Group**: (unassigned)

**Updated Fields (by SRE Agent)**:
- **Work Notes**: Log analysis results, memory metrics, root cause
- **Resolution Notes**: GitHub issue link, recommended actions
- **State**: Resolved (after investigation)

### GitHub Issue

**Title**: `Memory Leak Detected in Octopets API`

**Body**:
```markdown
## Incident Details
- **ServiceNow Incident**: INC0010001
- **Alert Rule**: High Memory Usage - Octopets API
- **Resource**: octopetsapi (Container App)
- **Time**: 2025-12-17T10:30:00Z

## Investigation Summary
Memory usage exceeded 80% threshold due to image loading without cleanup.

## Log Analysis
[KQL query results showing error patterns]

## Metrics
- Memory: 85% (threshold: 80%)
- CPU: 45%
- Error Rate: 15 errors/minute

## Root Cause
Memory leak in product details view when ERRORS=true environment variable set.

## Recommended Actions
1. Disable ERRORS flag: `az containerapp update -n octopetsapi -g rg-octopets-lab --set-env-vars "ERRORS=false"`
2. Restart container app to clear memory
3. Review image loading logic in ProductDetails component

## References
- ServiceNow: https://dev12345.service-now.com/incident.do?sysparm_query=number=INC0010001
- Log Analytics: [KQL query link]
```

### Email Notifications

**Subject**: `ServiceNow Incident INC0010001 - Octopets API Memory Leak`

**Content**:
- Incident summary
- Investigation results
- GitHub issue link
- Recommended actions
- ServiceNow incident link

## Alert Rule Details

### Alert 1: High Memory Usage

```bicep
Metric: WorkingSetBytes
Threshold: 80% of memory limit
Time Aggregation: Average
Evaluation Frequency: 1 minute
Window Size: 5 minutes
Severity: Warning (2)
Auto-Resolve: true
```

### Alert 2: Very High Memory Usage

```bicep
Metric: WorkingSetBytes
Threshold: 90% of memory limit
Time Aggregation: Average
Evaluation Frequency: 1 minute
Window Size: 3 minutes
Severity: Error (1)
Auto-Resolve: true
```

### Alert 3: High Error Rate

```bicep
Metric: Requests (failed)
Threshold: 10 failures per minute
Time Aggregation: Count
Evaluation Frequency: 1 minute
Window Size: 5 minutes
Severity: Warning (2)
Auto-Resolve: true
```

### Alert 4: Critical Error Rate

```bicep
Metric: Requests (failed)
Threshold: 50 failures per minute
Time Aggregation: Count
Evaluation Frequency: 1 minute
Window Size: 3 minutes
Severity: Critical (0)
Auto-Resolve: true
```

## ServiceNow REST API Integration

### Incident Creation Endpoint

**URL**: `https://{instance}.service-now.com/api/now/table/incident`

**Method**: POST

**Headers**:
```json
{
  "Content-Type": "application/json",
  "Accept": "application/json"
}
```

**Authentication**: Basic Auth (username/password)

**Payload**:
```json
{
  "short_description": "Octopets API - High Memory Usage Alert",
  "description": "Azure Monitor detected high memory usage in octopetsapi container app",
  "priority": "2",
  "category": "Software",
  "caller_id": "azure.monitor"
}
```

### Incident Query Endpoint

**URL**: `https://{instance}.service-now.com/api/now/table/incident`

**Method**: GET

**Query Parameters**:
```
sysparm_query=priority=1^ORpriority=2^state!=6^state!=7
sysparm_limit=10
sysparm_fields=sys_id,number,short_description,priority,state,sys_created_on
```

**Response** (used by SRE Agent):
```json
{
  "result": [
    {
      "sys_id": "abc123",
      "number": "INC0010001",
      "short_description": "Octopets API - High Memory Usage Alert",
      "priority": "2",
      "state": "1",
      "sys_created_on": "2025-12-17 10:30:00"
    }
  ]
}
```

### Incident Update Endpoint

**URL**: `https://{instance}.service-now.com/api/now/table/incident/{sys_id}`

**Method**: PATCH

**Payload**:
```json
{
  "work_notes": "Azure SRE Agent investigation complete. Root cause: Memory leak...",
  "resolution_notes": "GitHub issue created: https://github.com/...",
  "state": "6"
}
```

## SRE Agent Subagent Configuration

### System Prompt

The subagent is configured as a ServiceNow incident specialist that:
- Monitors for high-priority incidents (Priority 1 or 2)
- Investigates Azure resource issues using Log Analytics
- Creates detailed GitHub issues with root cause analysis
- Updates ServiceNow with resolution details
- Sends email notifications

### Workflow Steps

1. **Poll ServiceNow**: Every 2 minutes, query for new incidents
2. **Filter Incidents**: Priority 1-2, State = New/In Progress
3. **Extract Details**: Parse incident description for alert details
4. **Query Logs**: Use Log Analytics to find error patterns
5. **Analyze Metrics**: Check memory, CPU, error rates
6. **Create GitHub Issue**: Document findings with recommendations
7. **Update ServiceNow**: Add work notes, resolution notes, resolve incident
8. **Send Email**: Notify stakeholders with incident summary

### Connectors Used

- **ServiceNow Connector**: REST API for incident CRUD operations
- **GitHub Connector**: Issue creation via GitHub API
- **Outlook Connector**: Email notifications via Microsoft Graph
- **Azure Monitor**: Log Analytics queries via KQL

## Troubleshooting

### Alert Not Firing

```bash
# Check metric values
az monitor metrics list \
  --resource /subscriptions/.../octopetsapi \
  --metric WorkingSetBytes \
  --start-time 2025-12-17T10:00:00Z \
  --interval PT1M

# Verify alert rule enabled
az monitor metrics alert show \
  -n "High Memory Usage - Octopets API" \
  -g rg-octopets-lab \
  --query "enabled"

# Check action group
az monitor action-group show \
  -n "ServiceNow-ActionGroup" \
  -g rg-octopets-lab
```

### ServiceNow Incident Not Created

```bash
# Test webhook manually
curl -X POST \
  -H "Content-Type: application/json" \
  -u "$SERVICENOW_USERNAME:$SERVICENOW_PASSWORD" \
  -d '{"short_description":"Test Alert","priority":"2"}' \
  "https://$SERVICENOW_INSTANCE.service-now.com/api/now/table/incident"

# Check Azure Monitor activity log
az monitor activity-log list \
  --resource-group rg-octopets-lab \
  --start-time 2025-12-17T10:00:00Z \
  --query "[?contains(operationName.value, 'Alert')]"
```

### SRE Agent Not Processing Incident

```bash
# Check SRE Agent logs
# Azure Portal → rg-sre-agent-lab → sre-agent-lab → Logs
# KQL: ContainerAppConsoleLogs_CL | where TimeGenerated > ago(1h)

# Verify subagent enabled
# Azure Portal → SRE Agent → Subagent Builder → Check "ServiceNow Incident" enabled

# Test ServiceNow query manually
curl -X GET \
  -H "Accept: application/json" \
  -u "$SERVICENOW_USERNAME:$SERVICENOW_PASSWORD" \
  "https://$SERVICENOW_INSTANCE.service-now.com/api/now/table/incident?sysparm_query=priority=1^ORpriority=2&sysparm_limit=10"
```

### GitHub Issue Not Created

```bash
# Verify SRE Agent has GitHub connector configured
# Azure Portal → SRE Agent → Connectors → GitHub

# Check RBAC permissions
az role assignment list \
  --assignee <sre-agent-managed-identity-id> \
  --scope /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/rg-octopets-lab

# Verify GitHub repository access
# GitHub → Settings → Integrations → Azure SRE Agent
```

### Email Not Received

```bash
# Verify Outlook connector configured
# Azure Portal → SRE Agent → Connectors → Outlook

# Check email address in subagent YAML
# Search for: <INSERT_YOUR_EMAIL_HERE>

# Verify managed identity has Mail.Send permission
# Entra ID → Managed Identity → API Permissions
```

## Cleanup

### Disable Memory Leak

```bash
az containerapp update \
  -n octopetsapi \
  -g rg-octopets-lab \
  --set-env-vars "ERRORS=false"
```

### Delete Alert Rules

```bash
az monitor metrics alert delete \
  -n "High Memory Usage - Octopets API" \
  -g rg-octopets-lab

az monitor metrics alert delete \
  -n "Very High Memory Usage - Octopets API" \
  -g rg-octopets-lab

az monitor metrics alert delete \
  -n "High Error Rate - Octopets API" \
  -g rg-octopets-lab

az monitor metrics alert delete \
  -n "Critical Error Rate - Octopets API" \
  -g rg-octopets-lab

az monitor action-group delete \
  -n "ServiceNow-ActionGroup" \
  -g rg-octopets-lab
```

### Delete ServiceNow Incidents

```bash
# Manual cleanup via ServiceNow UI
# ServiceNow → Incident → Select all → Delete
```

### Disable SRE Agent Subagent

```bash
# Azure Portal → rg-sre-agent-lab → sre-agent-lab
# Subagent Builder → ServiceNow Incident → Disable/Delete
```

## Cost Considerations

### Azure Resources

- **Alert Rules**: Free (up to 10 metric alerts per subscription)
- **Action Group**: Free
- **Log Analytics**: Pay-per-GB ingestion (~$2.30/GB)
- **Application Insights**: Included with Container Apps
- **SRE Agent**: Preview pricing TBD

### ServiceNow

- **Developer Instance**: Free (personal use only)
- **Production Instance**: Requires license

### Estimated Demo Cost

- **Single demo execution**: < $0.10
- **Daily testing (10 runs)**: < $1.00
- **Monthly lab environment**: ~$50-100 (Container Apps + Log Analytics)

## References

### Documentation

- [Azure SRE Agent](https://github.com/microsoft/sre-agent)
- [ServiceNow REST API](https://docs.servicenow.com/bundle/vancouver-api-reference/page/integrate/inbound-rest/concept/c_RESTAPI.html)
- [Azure Monitor Alerts](https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-overview)
- [Container Apps Metrics](https://learn.microsoft.com/azure/container-apps/observability)

### Sample Code

- [PagerDuty Subagent](external/sre-agent/samples/automation/subagents/pd-azure-resource-error-handler.yaml)
- [Octopets Sample App](https://github.com/Azure-Samples/octopets)

### Tools

- [ServiceNow Developer Portal](https://developer.servicenow.com/)
- [Azure CLI Reference](https://learn.microsoft.com/cli/azure/)
- [KQL Quick Reference](https://learn.microsoft.com/azure/data-explorer/kql-quick-reference)

## Appendix: Complete File Contents

See individual files in the `demo/` directory:
- `servicenow-azure-resource-error-handler.yaml`
- `octopets-alert-rules.bicep`
- `README.md`

See deployment script:
- `scripts/50-deploy-alert-rules.sh`

See environment template:
- `.env.example` (updated with ServiceNow variables)
