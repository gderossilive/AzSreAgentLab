# Octopets API Memory Fix

## Issue: INC0010008 - High Memory Usage

This patch addresses the high memory usage issue in the Octopets API that was causing memory consumption to reach ~0.87 GiB (86% of the 1Gi limit).

## Root Cause

The issue was caused by a deliberate memory leak in `backend/Endpoints/ListingEndpoints.cs`:
- A function `AReallyExpensiveOperation()` allocated ~1GB of memory (10 × 100MB byte arrays)
- This function was triggered when the `ERRORS` environment variable was set to `true`
- The `ERRORS` flag was automatically set to `true` in production mode via `apphost/Program.cs`

## Changes Made

### 1. Code Changes (apply with `git apply octopets-memory-fix.patch`)

**backend/Endpoints/ListingEndpoints.cs:**
- ✅ Removed `AReallyExpensiveOperation()` function (lines 7-33)
- ✅ Removed `ERRORS` flag check in GET `/api/listings/{id}` endpoint
- ✅ Simplified endpoint to remove `IConfiguration config` dependency

**backend/Program.cs:**
- ✅ Added `/health/live` endpoint for liveness probes
- ✅ Added `/health/ready` endpoint for readiness probes

**apphost/Program.cs:**
- ✅ Removed `ERRORS` environment variable configuration (line 5)

### 2. Infrastructure Changes (via deployment scripts)

**scripts/31-deploy-octopets-containers.sh:**
- ✅ Increased memory limit from 1Gi to 2Gi
- ✅ Added explicit CPU (0.5) and memory (2Gi) configuration
- ✅ Reduced HTTP concurrency from 10 to 5 requests per replica
- ✅ Added min/max replica configuration (1-3)

**scripts/32-configure-health-probes.sh (new):**
- ✅ Configures liveness probe on `/health/live` (every 10s after 30s initial delay)
- ✅ Configures readiness probe on `/health/ready` (every 5s after 5s initial delay)

## Applying the Fix

### Option 1: Apply the patch (Recommended for development)

```bash
cd external/octopets
git apply ../../demo/octopets-memory-fix.patch
```

### Option 2: Manual changes

Review the patch file and apply changes manually to the octopets repository.

### Deploy the fixed version

```bash
# After applying the patch, rebuild and redeploy
source scripts/load-env.sh
scripts/31-deploy-octopets-containers.sh
```

## Expected Results

After applying the fix:
- Memory usage should stabilize at ~110-120 MiB (6-7% of 2Gi limit)
- No more deliberate memory allocations
- Better health monitoring with liveness/readiness probes
- Improved scaling behavior with lower concurrency threshold

## Verification

Monitor memory metrics after deployment:
```bash
scripts/61-check-memory.sh
```

Check the alert status in Azure Portal or via CLI:
```bash
az monitor metrics alert list -g rg-octopets-lab -o table
```

## Security Note

This fix removes test/demo code that should never have been in production. The `ERRORS` flag was designed for testing but was incorrectly enabled in production mode.
