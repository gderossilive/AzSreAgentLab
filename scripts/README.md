# Lab helper scripts

Run these from the repo root:

```bash
source scripts/load-env.sh
scripts/10-clone-repos.sh
scripts/20-az-login.sh
scripts/30-deploy-octopets.sh  # provisions Octopets infrastructure via azd
scripts/31-deploy-octopets-containers.sh  # builds/deploys containers via ACR (no Docker)
scripts/32-configure-health-probes.sh  # configures health probes (liveness + readiness)
scripts/35-apply-memory-fix.sh  # applies memory fix patch (INC0010008)
scripts/40-deploy-sre-agent.sh  # deploys SRE Agent via Bicep
scripts/50-deploy-alert-rules.sh  # deploys alert rules with ServiceNow integration
scripts/60-generate-traffic.sh  # generates test traffic
scripts/61-check-memory.sh  # checks memory usage metrics
```

## Memory Fix (INC0010008)

To apply the fix for high memory usage incident:

```bash
scripts/35-apply-memory-fix.sh  # Apply code changes
scripts/31-deploy-octopets-containers.sh  # Rebuild and redeploy
scripts/61-check-memory.sh  # Verify memory usage
```

See `demo/QUICK_REFERENCE_MEMORY_FIX.md` for details.
