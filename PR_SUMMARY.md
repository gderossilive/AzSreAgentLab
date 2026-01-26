# Pull Request Summary: Fix Octopets API 5xx Errors

## Overview

This PR addresses a Sev1 incident where the Octopets API experienced a spike in 5xx errors (75% error rate) on 2026-01-26 at 17:02 UTC. The root cause was fault injection flags (`CPU_STRESS=true`, `MEMORY_ERRORS=true`) combined with insufficient resiliency configuration.

## Changes Made

### 1. Infrastructure as Code (Bicep)

**New Files:**
- `infra/octopets/main.bicep` - Subscription-scoped deployment template
- `infra/octopets/resources.bicep` - Resource group-scoped infrastructure including:
  - Log Analytics Workspace
  - Application Insights
  - Azure Container Registry
  - Container Apps Environment
  - Container Apps (API & Frontend) with proper configuration

**Key Configuration Improvements:**
- ✅ Fault injection disabled by default (`CPU_STRESS=false`, `MEMORY_ERRORS=false`)
- ✅ Health probes configured (liveness & readiness on `/health` endpoint)
- ✅ High availability enabled (`minReplicas=2`, `maxReplicas=10`, was 1/1)
- ✅ Improved telemetry (`OTEL_METRICS_EXPORTER=otlp`, `OTEL_LOGS_EXPORTER=otlp`, was `none`)
- ✅ OpenTelemetry Collector sidecar for metrics/logs export to App Insights
- ✅ Managed Identity for ACR authentication (no admin credentials)
- ✅ RBAC role assignments (AcrPull scoped to Container Apps)

### 2. Deployment Scripts

**Modified:**
- `scripts/30-deploy-octopets.sh` - Updated to use `infra/octopets/main.bicep` instead of non-existent `external/octopets/apphost/infra/main.bicep`

**New:**
- `scripts/70-fix-octopets-api-config.sh` - Immediate fix script for existing deployments that:
  - Disables fault injection environment variables
  - Configures health probes via YAML
  - Increases replica count to 2
  - Enables OTEL telemetry exporters

### 3. Documentation

**New:**
- `docs/octopets-5xx-incident-fix.md` - Comprehensive incident response documentation including:
  - Incident summary and evidence
  - Root cause analysis
  - Fix implementation details
  - Deployment instructions
  - Verification steps
  - Rollback plan
  - Lessons learned

- `docs/octopets-5xx-validation-guide.md` - Complete validation and testing guide covering:
  - Pre-deployment validation (Bicep syntax, what-if deployment)
  - Deployment testing (new & existing deployments)
  - Post-deployment validation (configuration checks, health endpoints, metrics)
  - Load testing
  - Rollback testing
  - Security validation
  - Troubleshooting guide

**Modified:**
- `README.md` - Added incident reference section linking to documentation

## Security Considerations

- ✅ No secrets committed to source control
- ✅ `APPLICATIONINSIGHTS_CONNECTION_STRING` retrieved dynamically at deployment
- ✅ Managed Identity used for ACR authentication
- ✅ Least-privilege RBAC (AcrPull role scoped to specific resources)

## Testing

### Automated Validation Performed

1. ✅ Bicep syntax validation (`az bicep build`) - Passed
2. ✅ Bicep compilation to ARM JSON - Successful
3. ✅ Git commit hygiene - No secrets, no build artifacts committed

### Manual Testing Required (Azure Environment Needed)

- [ ] Deploy new environment using `scripts/30-deploy-octopets.sh`
- [ ] Deploy containers using `scripts/31-deploy-octopets-containers.sh`
- [ ] Verify health endpoint responds at `/health`
- [ ] Confirm 2 replicas are running
- [ ] Check health probes are configured and passing
- [ ] Verify environment variables are correct
- [ ] Monitor metrics for 30-60 minutes (5xx rate <1%, response time <500ms)
- [ ] Test immediate fix script on existing deployment

### Testing Plan

Refer to `docs/octopets-5xx-validation-guide.md` for comprehensive testing procedures.

## Deployment Instructions

### For New Deployments

```bash
source scripts/load-env.sh
./scripts/20-az-login.sh
./scripts/30-deploy-octopets.sh
./scripts/31-deploy-octopets-containers.sh
```

### For Existing Deployments (Immediate Fix)

```bash
source scripts/load-env.sh
./scripts/70-fix-octopets-api-config.sh
```

## Rollback Plan

If issues arise:
1. Disable fix: Re-enable fault injection using `scripts/63-enable-memory-errors.sh` (testing only)
2. Reduce replicas: `az containerapp update --min-replicas 1 --max-replicas 1` (not recommended)
3. Redeploy previous configuration via Bicep/YAML

## Impact Assessment

**Positive Impacts:**
- ✅ Eliminates 5xx errors caused by fault injection
- ✅ Improves availability with multiple replicas
- ✅ Enables proactive health monitoring via probes
- ✅ Better observability with OTEL metrics/logs
- ✅ Faster incident detection and recovery

**Potential Risks:**
- ⚠️ Increased infrastructure cost (2 replicas vs 1)
- ⚠️ Slightly increased complexity (health probes, telemetry)
- ⚠️ Requires health endpoint to be functional for probes to work

**Mitigation:**
- Cost increase is minimal (≈2x for API container, justified for production)
- Health endpoint already exists at `/health` in codebase
- Comprehensive documentation and testing guide provided

## Files Changed

```
 README.md                             |   4 +
 docs/octopets-5xx-incident-fix.md     | 188 +++++++++++
 docs/octopets-5xx-validation-guide.md | 293 ++++++++++++++++
 infra/octopets/main.bicep             |  44 +++
 infra/octopets/main.json              | 498 ++++++++++++++++++++++++++
 infra/octopets/resources.bicep        | 327 +++++++++++++++++
 infra/octopets/resources.json         | 396 +++++++++++++++++++++
 scripts/30-deploy-octopets.sh         |   4 +-
 scripts/70-fix-octopets-api-config.sh | 126 +++++++
 9 files changed, 1878 insertions(+), 2 deletions(-)
```

## Checklist

- [x] Code follows repository conventions
- [x] Bicep templates are syntactically valid
- [x] No secrets committed
- [x] Documentation is comprehensive
- [x] Deployment scripts updated
- [x] Validation guide provided
- [x] Rollback plan documented
- [ ] Tested in Azure environment (requires access)
- [ ] Metrics show improvement (requires deployment)

## References

- **Incident Alert**: [Azure Portal](https://portal.azure.com/#view/Microsoft_Azure_Monitoring_Alerts/Issue.ReactView/alertId/%2fsubscriptions%2f06dbbc7b-2363-4dd4-9803-95d07f1a8d3e%2fresourceGroups%2frg-octopets-demo-lab%2fproviders%2fMicrosoft.AlertsManagement%2falerts%2fa1a076ed-ae81-4d1d-b1fc-f569f583f000)
- **SRE Agent Thread**: [Azure Portal](https://portal.azure.com/?feature.customPortal=false&feature.canmodifystamps=true&feature.fastmanifest=false&nocdn=force&websitesextension_loglevel=verbose&Microsoft_Azure_PaasServerless=beta&microsoft_azure_paasserverless_assettypeoptions=%7B%22SreAgentCustomMenu%22%3A%7B%22options%22%3A%22%22%7D%7D#view/Microsoft_Azure_PaasServerless/AgentFrameBlade.ReactView/id/%2Fsubscriptions%2F06dbbc7b-2363-4dd4-9803-95d07f1a8d3e%2FresourceGroups%2Frg-sre-agent-demo%2Fproviders%2FMicrosoft.App%2Fagents%2Fsre-agent-demo/sreLink/%2Fviews%2Factivities%2Fthreads%2F178526a8-7f5f-4645-bdb1-43cfdd7e8d30)
- **Container App**: `/subscriptions/06dbbc7b-2363-4dd4-9803-95d07f1a8d3e/resourceGroups/rg-octopets-demo-lab/providers/Microsoft.App/containerApps/octopetsapi`
- **Issue**: Sev1: Octopets API 5xx spike at 17:02 UTC on 2026-01-26

---

This fix implements all proposed remediations from the incident report and provides comprehensive documentation for deployment, validation, and troubleshooting.
