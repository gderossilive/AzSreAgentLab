# Octopets API 5xx Error Fix - Sev1 Incident Response

## Incident Summary

**Alert**: HTTP 5xx - Octopets API (Metric Alert)  
**Fired**: 2026-01-26T17:02:20.797471Z (UTC)  
**Severity**: Sev1  
**Resource**: `/subscriptions/06dbbc7b-2363-4dd4-9803-95d07f1a8d3e/resourceGroups/rg-octopets-demo-lab/providers/Microsoft.App/containerApps/octopetsapi`

### Evidence

- High 5xx error rate during 16:57-17:02 UTC (≈75% of requests)
- Elevated response times (≈1100-2200ms)
- Single replica with `minReplicas=1`
- Fault injection flags enabled: `CPU_STRESS=true`, `MEMORY_ERRORS=true`
- No health probes configured
- Limited telemetry (OTEL metrics/logs exporters set to `none`)

## Root Cause

1. **Fault injection** enabled causing intentional failures under load
2. **Single replica** (minReplicas=1) creating single point of failure
3. **No health probes** preventing detection and replacement of unhealthy instances
4. **Limited telemetry** hampering diagnostics (OTEL metrics/logs disabled)

## Fix Implementation

### Changes Made

#### 1. Infrastructure as Code (Bicep)

Created/updated Bicep templates in `infra/octopets/`:

- **main.bicep**: Subscription-scoped deployment creating resource group and calling resources module
- **resources.bicep**: Complete infrastructure including:
  - Log Analytics Workspace
  - Application Insights
  - Azure Container Registry
  - Container Apps Environment
  - Octopets API Container App with:
    - `CPU_STRESS=false` and `MEMORY_ERRORS=false` (disabled fault injection)
    - Liveness and readiness health probes on `/health` endpoint
    - `minReplicas=2`, `maxReplicas=10` (high availability)
    - `OTEL_METRICS_EXPORTER=otlp` and `OTEL_LOGS_EXPORTER=otlp` (improved telemetry)
    - OpenTelemetry Collector sidecar for metrics/logs export
  - Octopets Frontend Container App
  - RBAC role assignments for ACR pull

#### 2. Deployment Scripts

- **Updated**: `scripts/30-deploy-octopets.sh` to reference `infra/octopets/main.bicep`
- **Created**: `scripts/70-fix-octopets-api-config.sh` - immediate fix script that:
  - Disables fault injection flags
  - Configures health probes
  - Increases replica count to 2
  - Enables OTEL metrics/logs exporters

### Health Probes Configuration

```yaml
Liveness Probe:
  Path: /health
  Port: 8080
  Initial Delay: 10s
  Period: 30s
  Failure Threshold: 3
  Timeout: 5s

Readiness Probe:
  Path: /health
  Port: 8080
  Initial Delay: 5s
  Period: 10s
  Failure Threshold: 3
  Timeout: 3s
```

### Scaling Configuration

```
Before: minReplicas=1, maxReplicas=1
After:  minReplicas=2, maxReplicas=10
HTTP Scaler: 10 concurrent requests
```

## Deployment

### For Existing Deployments (Immediate Fix)

Apply the fix to a running Container App:

```bash
source scripts/load-env.sh
./scripts/70-fix-octopets-api-config.sh
```

This script will:
1. Disable fault injection environment variables
2. Configure health probes
3. Increase replica count
4. Enable OTEL telemetry exporters

### For New Deployments

Use the updated Bicep infrastructure:

```bash
source scripts/load-env.sh
./scripts/20-az-login.sh
./scripts/30-deploy-octopets.sh  # Uses infra/octopets/main.bicep
./scripts/31-deploy-octopets-containers.sh
```

## Verification

After applying the fix, monitor for 30-60 minutes:

1. **Container Apps Metrics** (Azure Portal):
   - Requests: Verify 2xx increases, 5xx decreases to near-zero
   - Response Time: Should stabilize to <500ms
   - Replica Count: Should show 2 active replicas

2. **Application Insights**:
   - Requests table: Should now populate with request telemetry
   - Exceptions table: Should show any errors (if OTEL logs/metrics enabled)
   - Live Metrics: Real-time request rate and performance

3. **Container App Health**:
   - Check probe success rates in Container App Revision details
   - Verify no `CrashLoopBackOff` or replica restart events

4. **Logs** (Log Analytics):
   ```kql
   ContainerAppConsoleLogs_CL
   | where ContainerAppName_s == "octopetsapi"
   | where TimeGenerated > ago(1h)
   | project TimeGenerated, Log_s
   | order by TimeGenerated desc
   ```

## Security Notes

- No secrets committed to source control
- `APPLICATIONINSIGHTS_CONNECTION_STRING` is retrieved at deployment time
- Managed Identity used for ACR authentication (no admin credentials)
- Least-privilege RBAC (AcrPull role scoped to specific Container Apps)

## References

- Alert Investigation: [Azure Portal Link](https://portal.azure.com/#view/Microsoft_Azure_Monitoring_Alerts/Issue.ReactView/alertId/%2fsubscriptions%2f06dbbc7b-2363-4dd4-9803-95d07f1a8d3e%2fresourceGroups%2frg-octopets-demo-lab%2fproviders%2fMicrosoft.AlertsManagement%2falerts%2fa1a076ed-ae81-4d1d-b1fc-f569f583f000)
- SRE Agent Thread: [Azure Portal](https://portal.azure.com/?feature.customPortal=false&feature.canmodifystamps=true&feature.fastmanifest=false&nocdn=force&websitesextension_loglevel=verbose&Microsoft_Azure_PaasServerless=beta&microsoft_azure_paasserverless_assettypeoptions=%7B%22SreAgentCustomMenu%22%3A%7B%22options%22%3A%22%22%7D%7D#view/Microsoft_Azure_PaasServerless/AgentFrameBlade.ReactView/id/%2Fsubscriptions%2F06dbbc7b-2363-4dd4-9803-95d07f1a8d3e%2FresourceGroups%2Frg-sre-agent-demo%2Fproviders%2FMicrosoft.App%2Fagents%2Fsre-agent-demo/sreLink/%2Fviews%2Factivities%2Fthreads%2F178526a8-7f5f-4645-bdb1-43cfdd7e8d30)
- Container App Resource: `/subscriptions/06dbbc7b-2363-4dd4-9803-95d07f1a8d3e/resourceGroups/rg-octopets-demo-lab/providers/Microsoft.App/containerApps/octopetsapi`

## Rollback Plan

If issues arise after applying the fix:

1. **Restore fault injection** (testing only):
   ```bash
   ./scripts/63-enable-memory-errors.sh
   # or
   ./scripts/61-enable-cpu-stress.sh
   ```

2. **Reduce replicas** (not recommended for production):
   ```bash
   az containerapp update \
     -n octopetsapi \
     -g "$OCTOPETS_RG_NAME" \
     --min-replicas 1 \
     --max-replicas 1
   ```

3. **Remove health probes** (not recommended):
   Redeploy without probes configuration via Bicep/YAML

## Lessons Learned

1. **Always disable fault injection in production** - Use separate test environments
2. **Health probes are essential** - Enable liveness and readiness probes for all services
3. **Avoid single replicas** - Use minReplicas >= 2 for production workloads
4. **Enable comprehensive telemetry** - OTEL metrics and logs provide critical visibility
5. **Test scaling before production** - Validate autoscaling rules handle expected load

---

*Incident response completed: 2026-01-26*  
*PR: [Link to Pull Request]*
