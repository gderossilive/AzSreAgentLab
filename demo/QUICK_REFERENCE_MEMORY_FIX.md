# Quick Reference: Memory Fix Deployment

## TL;DR
Fix for incident INC0010008 - removes test code causing 1GB memory allocations in production.

## One-Command Deploy
```bash
cd /home/runner/work/AzSreAgentLab/AzSreAgentLab
source scripts/load-env.sh && \
scripts/35-apply-memory-fix.sh && \
scripts/31-deploy-octopets-containers.sh
```

## What Gets Fixed
- ❌ Removes `AReallyExpensiveOperation()` that allocated 1GB memory
- ❌ Removes `ERRORS=true` flag from production
- ✅ Adds health endpoints: `/health/live`, `/health/ready`
- ✅ Increases memory limit: 1Gi → 2Gi
- ✅ Reduces concurrency: 10 → 5 req/replica
- ✅ Configures health probes (liveness + readiness)

## Expected Results
| Metric | Before | After |
|--------|--------|-------|
| Memory Usage | ~870 MiB | ~110-120 MiB |
| Memory % | 86% of 1Gi | 6-7% of 2Gi |
| Alert Status | Triggered | Resolved |

## Verification
```bash
# Check memory usage
scripts/61-check-memory.sh

# View container app status
az containerapp show -n octopetsapi -g rg-octopets-lab \
  --query "properties.{status:runningStatus,memory:template.containers[0].resources.memory,replicas:template.scale}"

# Check health endpoints
curl https://$(az containerapp show -n octopetsapi -g rg-octopets-lab --query "properties.configuration.ingress.fqdn" -o tsv)/health/live
curl https://$(az containerapp show -n octopetsapi -g rg-octopets-lab --query "properties.configuration.ingress.fqdn" -o tsv)/health/ready
```

## Rollback (if needed)
```bash
cd external/octopets
git checkout backend/Endpoints/ListingEndpoints.cs backend/Program.cs apphost/Program.cs

# Redeploy previous version
cd /home/runner/work/AzSreAgentLab/AzSreAgentLab
scripts/31-deploy-octopets-containers.sh
```

## Troubleshooting

### Patch fails to apply
```bash
# Check octopets directory state
cd external/octopets
git status

# If dirty, either commit or reset
git checkout .  # Reset to clean state
# OR
git stash      # Save changes for later

# Retry
cd /home/runner/work/AzSreAgentLab/AzSreAgentLab
scripts/35-apply-memory-fix.sh
```

### Deployment fails
```bash
# Check Azure CLI authentication
az account show

# Re-authenticate if needed
scripts/20-az-login.sh

# Check resource group exists
az group show -n rg-octopets-lab

# Retry deployment
scripts/31-deploy-octopets-containers.sh
```

### Memory still high after deployment
```bash
# Verify correct image is deployed
az containerapp show -n octopetsapi -g rg-octopets-lab \
  --query "properties.template.containers[0].image" -o tsv

# Check environment variables
az containerapp show -n octopetsapi -g rg-octopets-lab \
  --query "properties.template.containers[0].env" -o json

# Look for ERRORS=true (should NOT be present)
# If present, remove it:
az containerapp update -n octopetsapi -g rg-octopets-lab \
  --remove-env-vars "ERRORS"
```

## Files Modified
- ✅ `scripts/31-deploy-octopets-containers.sh` - deployment config
- ✅ `scripts/32-configure-health-probes.sh` - health probe setup (new)
- ✅ `scripts/35-apply-memory-fix.sh` - patch applicator (new)
- ✅ `demo/octopets-memory-fix.patch` - code changes (new)
- ✅ `demo/OCTOPETS_MEMORY_FIX.md` - detailed docs (new)
- ✅ `demo/INCIDENT_RESPONSE_INC0010008.md` - incident summary (new)

## Support
- **Detailed Documentation:** `demo/OCTOPETS_MEMORY_FIX.md`
- **Incident Summary:** `demo/INCIDENT_RESPONSE_INC0010008.md`
- **ServiceNow Ticket:** INC0010008
- **Alert Rule:** High Memory Usage - Octopets API

## Contact
- **SRE Agent:** sre-agent-lab--755504d1
- **GitHub Issue:** [Link in original incident]
- **Azure Portal:** Sweden Central, rg-octopets-lab
