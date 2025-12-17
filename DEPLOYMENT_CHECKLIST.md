# Deployment Checklist - INC0010008 Memory Fix

## Pre-Deployment Validation ✅

- [x] **Code Review:** Completed, all feedback addressed
- [x] **Build Verification:** dotnet build - 0 errors, 0 warnings
- [x] **Security Scan:** CodeQL passed - no vulnerabilities
- [x] **Patch Testing:** Clean apply + rollback verified
- [x] **Documentation:** Complete (1,247 lines)
- [x] **Scripts:** Validated and executable (124 lines)

## Deployment Checklist

### Phase 1: Pre-Deployment (5 minutes)
- [ ] Review incident details: `demo/INCIDENT_RESPONSE_INC0010008.md`
- [ ] Review deployment guide: `demo/QUICK_REFERENCE_MEMORY_FIX.md`
- [ ] Verify Azure CLI authentication: `az account show`
- [ ] Load environment variables: `source scripts/load-env.sh`
- [ ] Verify resource group exists: `az group show -n rg-octopets-lab`
- [ ] Check current memory usage: `scripts/61-check-memory.sh`
- [ ] Take note of current memory baseline (should be ~870 MiB)

### Phase 2: Code Changes (2 minutes)
- [ ] Navigate to repo root: `cd /home/runner/work/AzSreAgentLab/AzSreAgentLab`
- [ ] Apply memory fix patch: `scripts/35-apply-memory-fix.sh`
- [ ] Verify patch applied successfully (look for ✅ in output)
- [ ] Optional: Review changes: `cd external/octopets && git diff`

### Phase 3: Container Deployment (10-15 minutes)
- [ ] Return to repo root: `cd /home/runner/work/AzSreAgentLab/AzSreAgentLab`
- [ ] Deploy containers: `scripts/31-deploy-octopets-containers.sh`
  - Builds backend image with fixes (~5 min)
  - Builds frontend image (~3 min)
  - Updates container apps with new resources
  - Configures health probes automatically
- [ ] Wait for deployment to complete
- [ ] Verify no errors in deployment output

### Phase 4: Health Probe Configuration (2 minutes)
- [ ] Health probes configured automatically by deployment script
- [ ] Verify configuration: 
  ```bash
  az containerapp show -n octopetsapi -g rg-octopets-lab \
    --query "properties.template.containers[0].probes" -o json
  ```
- [ ] Should see liveness and readiness probes configured

### Phase 5: Verification (5 minutes)
- [ ] Check memory usage: `scripts/61-check-memory.sh`
- [ ] Expected: ~110-120 MiB (down from ~870 MiB)
- [ ] Test health endpoints:
  ```bash
  API_URL=$(az containerapp show -n octopetsapi -g rg-octopets-lab --query "properties.configuration.ingress.fqdn" -o tsv)
  curl https://$API_URL/health/live
  curl https://$API_URL/health/ready
  ```
- [ ] Both should return status 200 with JSON response
- [ ] Test API functionality:
  ```bash
  curl https://$API_URL/api/listings
  ```
- [ ] Should return listings JSON (not errors)
- [ ] Check container app status:
  ```bash
  az containerapp show -n octopetsapi -g rg-octopets-lab \
    --query "properties.{status:runningStatus,replicas:template.scale}" -o json
  ```

### Phase 6: Monitoring (30 minutes)
- [ ] Monitor memory metrics in Azure Portal
- [ ] Watch for alert re-triggers (should NOT happen)
- [ ] Check Application Insights for errors
- [ ] Verify response times remain normal
- [ ] Monitor replica count (should be 1-3)
- [ ] Check logs for any warnings/errors:
  ```bash
  az containerapp logs show -n octopetsapi -g rg-octopets-lab --tail 50
  ```

### Phase 7: Post-Deployment (5 minutes)
- [ ] Update incident ticket (INC0010008) with deployment time
- [ ] Document memory usage improvement in ticket
- [ ] Schedule 24-hour follow-up check
- [ ] Notify stakeholders of successful deployment

## Success Criteria

### ✅ Deployment Successful If:
- Memory usage < 200 MiB (target: 110-120 MiB)
- Memory percentage < 20% of 2Gi limit
- Health endpoints responding with 200 OK
- API endpoints functioning normally
- No errors in container logs
- Alert does not re-trigger within 1 hour

### ⚠️ Investigation Required If:
- Memory usage > 500 MiB after deployment
- Health endpoints return errors
- API endpoints return 5xx errors
- Container restarts occur
- Alert re-triggers within 1 hour

### 🔴 Rollback Required If:
- Memory usage > 1.5Gi after deployment
- API completely unavailable
- Multiple container restarts
- Critical functionality broken
- Security issues detected

## Rollback Procedure

If deployment fails or causes issues:

```bash
cd /home/runner/work/AzSreAgentLab/AzSreAgentLab/external/octopets
git checkout backend/Endpoints/ListingEndpoints.cs \
            backend/Program.cs \
            apphost/Program.cs
cd /home/runner/work/AzSreAgentLab/AzSreAgentLab
scripts/31-deploy-octopets-containers.sh
```

**Note:** Rollback will restore the memory leak, so only use if the fix causes worse issues.

## Estimated Timeline

| Phase | Duration | Cumulative |
|-------|----------|------------|
| Pre-Deployment | 5 min | 5 min |
| Code Changes | 2 min | 7 min |
| Container Deployment | 10-15 min | 17-22 min |
| Health Probe Config | 2 min | 19-24 min |
| Verification | 5 min | 24-29 min |
| Monitoring | 30 min | 54-59 min |
| Post-Deployment | 5 min | 59-64 min |

**Total Time:** ~60 minutes (end-to-end)  
**Hands-on Time:** ~20 minutes  
**Wait Time:** ~40 minutes (builds + monitoring)

## Quick Reference Commands

```bash
# Complete deployment in one command
source scripts/load-env.sh && \
scripts/35-apply-memory-fix.sh && \
scripts/31-deploy-octopets-containers.sh

# Verify deployment
scripts/61-check-memory.sh

# Check health
API_URL=$(az containerapp show -n octopetsapi -g rg-octopets-lab --query "properties.configuration.ingress.fqdn" -o tsv)
curl https://$API_URL/health/live
curl https://$API_URL/health/ready

# Rollback (if needed)
cd external/octopets && git checkout backend/ apphost/ && cd ../.. && scripts/31-deploy-octopets-containers.sh
```

## Documentation References

- **Quick Guide:** `demo/QUICK_REFERENCE_MEMORY_FIX.md`
- **Detailed Fix:** `demo/OCTOPETS_MEMORY_FIX.md`
- **Incident Report:** `demo/INCIDENT_RESPONSE_INC0010008.md`
- **PR Summary:** `PULL_REQUEST_SUMMARY.md`

## Support Contacts

- **Incident:** INC0010008 (ServiceNow)
- **SRE Agent:** sre-agent-lab--755504d1
- **Resource Group:** rg-octopets-lab (Sweden Central)
- **Pull Request:** [Link to PR]

## Sign-off

- [ ] Pre-deployment review completed
- [ ] Deployment executed successfully
- [ ] Verification passed
- [ ] Monitoring completed (30 min)
- [ ] Incident ticket updated
- [ ] Stakeholders notified

**Deployed by:** ___________________  
**Date/Time:** ___________________  
**Final Memory Usage:** ___________ MiB  
**Alert Status:** ___________________  

---

**Version:** 1.0  
**Last Updated:** 2025-12-17  
**Incident:** INC0010008
