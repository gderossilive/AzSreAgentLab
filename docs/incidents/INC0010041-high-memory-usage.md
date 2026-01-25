# Incident INC0010041: High Memory Usage - Octopets API

## Summary
ServiceNow incident triggered by Azure Monitor alert for high memory usage in the Octopets API container app. The incident was caused by the `MEMORY_ERRORS=true` demo flag being enabled, which allocates 1GB of memory per API call.

## Incident Details
- **Incident ID**: INC0010041
- **Severity**: Sev3
- **Date**: 2026-01-25
- **Resolution Time**: 2026-01-25T13:43:50Z
- **Affected Resource**: Container App octopetsapi (revision octopetsapi--0000024)
- **Resource ID**: `/subscriptions/06dbbc7b-2363-4dd4-9803-95d07f1a8d3e/resourceGroups/rg-octopets-demo-lab/providers/Microsoft.App/containerapps/octopetsapi`

## Root Cause
The demo feature `MEMORY_ERRORS=true` was enabled in the production environment, causing the backend API to allocate 1GB of memory on each API call. This quickly exhausted the container's 1Gi memory limit, triggering the alert.

### Evidence
- WorkingSetBytes rose rapidly around 10:52Z UTC and plateaued at ~940-960MB until 13:38Z
- MemoryPercentage peaked at ~56% (container metric)
- Alert threshold: WorkingSetBytes > 858,993,459 bytes (80% of 1Gi) for 5 minutes
- Sharp drop at 13:39-13:40Z to ~148-416MB after MEMORY_ERRORS was disabled

## Implemented Fixes

### 1. Alert Configuration Improvements (`demos/ServiceNowAzureResourceHandler/octopets-service-now-alerts.bicep`)
**Problem**: Memory alert used hardcoded WorkingSetBytes threshold (858,993,459 bytes) that wouldn't adapt to container memory changes.

**Fix**: 
- Switched from `WorkingSetBytes > 858993459` to `MemoryPercentage > 80`
- Updated both 80% and 90% memory alerts
- Alerts now automatically adapt to any container memory configuration changes

### 2. Production Safeguards (`scripts/63-enable-memory-errors.sh`)
**Problem**: No protection against accidentally enabling MEMORY_ERRORS in production.

**Fix**:
- Added environment check that blocks enabling MEMORY_ERRORS in Production
- Added confirmation prompt for non-production environments
- Improved warning messages with incident reference

### 3. Deployment Guardrails (`scripts/31-deploy-octopets-containers.sh`)
**Problem**: Container deployments didn't enforce safe defaults.

**Fix**:
- Explicitly set `MEMORY_ERRORS=false` on container create/update
- Added `ASPNETCORE_ENVIRONMENT=Production` to enforce production behavior
- Added `DOTNET_GCHeapHardLimitPercent=70` to prevent GC heap from consuming full container memory

### 4. Auto-Scaling Configuration (`demos/ServiceNowAzureResourceHandler/octopets-autoscaling.bicep`)
**Problem**: Container app had `maxReplicas=1`, preventing scale-out on memory pressure.

**Fix**:
- Created Bicep template to configure KEDA-based auto-scaling
- Set `minReplicas=1`, `maxReplicas=3`
- Added three scaling rules:
  - CPU utilization > 70%
  - Memory utilization > 70%
  - HTTP concurrent requests > 10
- Created deployment script `scripts/67-deploy-autoscaling.sh`

## Deployment Instructions

### Deploy Updated Alert Rules
```bash
source scripts/load-env.sh

# Deploy updated ServiceNow alerts with MemoryPercentage metrics
az deployment group create \
  --resource-group "$OCTOPETS_RG_NAME" \
  --template-file demos/ServiceNowAzureResourceHandler/octopets-service-now-alerts.bicep \
  --parameters \
    subscriptionId="$AZURE_SUBSCRIPTION_ID" \
    resourceGroupName="$OCTOPETS_RG_NAME" \
    serviceNowInstanceUrl="$SERVICENOW_INSTANCE" \
    serviceNowWebhookUrl="$SERVICENOW_WEBHOOK_URL"
```

### Deploy Auto-Scaling Configuration
```bash
source scripts/load-env.sh
scripts/67-deploy-autoscaling.sh
```

### Redeploy Container App with Safeguards
```bash
source scripts/load-env.sh
scripts/31-deploy-octopets-containers.sh
```

## Prevention Measures

### For Developers
1. **Never enable MEMORY_ERRORS in production**: The script now blocks this, but if you need to override for testing, explicitly set `ASPNETCORE_ENVIRONMENT=Development`
2. **Use auto-scaling**: The container app now scales horizontally when memory or CPU pressure increases
3. **Monitor memory percentage, not absolute bytes**: Alerts now use MemoryPercentage which adapts to container size changes

### For Operations
1. **Alert review**: Memory alerts now use percentage-based thresholds that work regardless of container memory configuration
2. **Scaling configuration**: Review and adjust maxReplicas (currently 3) based on production load requirements
3. **GC heap limit**: The .NET GC is now limited to 70% of container memory to leave headroom for runtime overhead

## Testing and Validation

### Test Memory Stress (Non-Production Only)
```bash
# This will fail in production environments
export ASPNETCORE_ENVIRONMENT=Development
source scripts/load-env.sh
scripts/63-enable-memory-errors.sh

# Generate traffic to trigger scaling
scripts/60-generate-traffic.sh 20

# Monitor memory usage
scripts/61-check-memory.sh

# Disable memory errors
scripts/64-disable-memory-errors.sh
```

### Verify Auto-Scaling
```bash
source scripts/load-env.sh

# Check current replica count
az containerapp show \
  --name octopetsapi \
  --resource-group "$OCTOPETS_RG_NAME" \
  --query 'properties.template.scale' \
  -o json
```

## Related Files
- Alert configuration: `demos/ServiceNowAzureResourceHandler/octopets-service-now-alerts.bicep`
- Auto-scaling: `demos/ServiceNowAzureResourceHandler/octopets-autoscaling.bicep`
- Deployment script: `scripts/31-deploy-octopets-containers.sh`
- Memory stress script: `scripts/63-enable-memory-errors.sh`
- Auto-scaling deployment: `scripts/67-deploy-autoscaling.sh`

## References
- Azure Portal Alert: https://portal.azure.com/#view/Microsoft_Azure_Monitoring_Alerts/Issue.ReactView/alertId/%2fsubscriptions%2f06dbbc7b-2363-4dd4-9803-95d07f1a8d3e%2fresourceGroups%2frg-octopets-demo-lab%2fproviders%2fMicrosoft.AlertsManagement%2falerts%2fe8c60e97-f33d-4a65-8188-0c6b499df000
- Container App: `/subscriptions/06dbbc7b-2363-4dd4-9803-95d07f1a8d3e/resourceGroups/rg-octopets-demo-lab/providers/Microsoft.App/containerapps/octopetsapi`
- SRE Agent Activity: https://portal.azure.com/?feature.customPortal=false&feature.canmodifystamps=true&feature.fastmanifest=false&nocdn=force&websitesextension_loglevel=verbose&Microsoft_Azure_PaasServerless=beta&microsoft_azure_paasserverless_assettypeoptions=%7B%22SreAgentCustomMenu%22%3A%7B%22options%22%3A%22%22%7D%7D#view/Microsoft_Azure_PaasServerless/AgentFrameBlade.ReactView/id/%2Fsubscriptions%2F06dbbc7b-2363-4dd4-9803-95d07f1a8d3e%2FresourceGroups%2Frg-sre-agent-demo%2Fproviders%2FMicrosoft.App%2Fagents%2Fsre-agent-demo/sreLink/%2Fviews%2Factivities%2Fthreads%2F49b58ee4-8073-4e25-8c2a-87da880618c1
