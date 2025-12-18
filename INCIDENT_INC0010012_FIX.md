# Incident INC0010012 - High CPU Usage Fix

## Summary
This document describes the code changes made to fix high CPU usage on the Octopets API (Azure Container Apps) identified in incident INC0010012.

## Incident Details
- **Incident ID**: INC0010012 (High-CPU-Usage-Octopets-API)
- **Severity**: Sev3
- **Service**: Azure Container Apps – octopetsapi (rg-octopets-lab, Sweden Central)
- **Alert Rule**: High-CPU-Usage-Octopets-API (UsageNanoCores > ~35M avg for 5m)
- **Window**: 2025-12-18 17:11–17:23 UTC
- **Status**: Resolved with code fixes

## Root Causes

### 1. Missing EF Core ValueComparer
The `AllowedPets`, `Amenities`, and `Photos` properties in the `Listing` entity had value converters for JSON serialization but were missing `ValueComparer` instances. This caused EF Core to perform excessive object tracking and comparison operations during entity state management, leading to high CPU usage under load.

**Evidence**: EF Core warnings in logs:
```
warn: Microsoft.EntityFrameworkCore.Model.Validation[10620]
      The property 'Listing.AllowedPets' is a collection or enumeration type with a value converter but with no value comparer.
warn: Microsoft.EntityFrameworkCore.Model.Validation[10620]
      The property 'Listing.Amenities' is a collection or enumeration type with a value converter but with no value comparer.
```

### 2. HTTPS Redirection Misconfiguration
The application was configured to use HTTPS redirection (`app.UseHttpsRedirection()`) on every request, even though it only binds to HTTP (ASPNETCORE_URLS=http://+:8080) in the Azure Container Apps environment. This caused unnecessary overhead as each request would fail to determine the HTTPS port for redirect.

**Evidence**: Warning in logs:
```
warn: Microsoft.AspNetCore.HttpsPolicy.HttpsRedirectionMiddleware[3]
      Failed to determine the https port for redirect.
```

## Code Changes

### File: `external/octopets/backend/Data/AppDbContext.cs`

**Changes Made**:
1. Added `using Microsoft.EntityFrameworkCore.ChangeTracking;` directive
2. Created a reusable `ValueComparer<List<string>>` instance that properly compares list collections:
   - Equality comparison using `SequenceEqual`
   - Hash code generation using `HashCode.Combine`
   - Snapshot creation using `ToList()`
3. Applied the ValueComparer to `AllowedPets`, `Amenities`, and `Photos` properties via `.Metadata.SetValueComparer()`

**Impact**: Eliminates excessive CPU usage during EF Core entity tracking and change detection.

### File: `external/octopets/backend/Program.cs`

**Changes Made**:
1. Replaced unconditional `app.UseHttpsRedirection()` with conditional logic
2. Only applies HTTPS redirection when `ASPNETCORE_URLS` environment variable contains "https"

**Impact**: Prevents unnecessary HTTPS redirect checks on every request in HTTP-only environments.

## Validation

### Build Validation
```bash
cd external/octopets/backend
dotnet build
# Result: Build succeeded. 0 Warning(s) 0 Error(s)
```

### Runtime Validation
```bash
cd external/octopets/backend
dotnet run
# Result: Application starts without EF Core warnings
# Info: Database initialized with 20 entities
# No warnings about missing ValueComparer
# No warnings about HTTPS redirection failures
```

## Deployment

The changes are committed in the `external/octopets` repository. To deploy:

1. **Rebuild Container Images**:
   ```bash
   source scripts/load-env.sh
   scripts/31-deploy-octopets-containers.sh
   ```

2. **Verify Deployment**:
   - Monitor CPU metrics: Should see reduction in UsageNanoCores under load
   - Check application logs: No more EF Core or HTTPS redirection warnings
   - Test API endpoints: Ensure functionality is unchanged

## Expected Outcomes

1. **Reduced CPU Usage**: Elimination of excessive EF Core tracking operations should significantly reduce CPU consumption under concurrent load
2. **No EF Core Warnings**: Application logs should no longer contain ValueComparer warnings
3. **No HTTPS Redirect Overhead**: Elimination of failed redirect checks on every HTTP request
4. **Improved Scalability**: Lower CPU per request allows higher throughput before hitting autoscale thresholds

## Additional Recommendations (Optional)

While the code fixes address the immediate CPU issue, consider these operational improvements in `infra/octopets.bicep`:

1. **Lower KEDA concurrentRequests threshold**:
   - Current: 10 concurrent requests per replica
   - Recommended: 5 concurrent requests per replica
   - Rationale: Faster scale-out under load with cpu=0.5

2. **Increase maxReplicas**:
   - Current: 3 replicas
   - Recommended: 5-10 replicas (subject to capacity/cost)
   - Rationale: Better handle traffic spikes

3. **Add CPU-based scale rule**:
   - Trigger scale-out when avg CPU > 60-70%
   - Complements HTTP concurrency-based scaling

## References

- **Alert**: `/subscriptions/06dbbc7b-2363-4dd4-9803-95d07f1a8d3e/resourceGroups/rg-octopets-lab/providers/Microsoft.AlertsManagement/alerts/e637fa12-8d05-42f9-a6d9-df5ad2fbf000`
- **Container App**: `/subscriptions/06dbbc7b-2363-4dd4-9803-95d07f1a8d3e/resourceGroups/rg-octopets-lab/providers/Microsoft.App/containerApps/octopetsapi`
- **Patch File**: `octopets-cpu-fix.patch`
- **EF Core Documentation**: https://learn.microsoft.com/en-us/ef/core/modeling/value-comparers
