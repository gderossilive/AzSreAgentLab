# Octopets - Vendored Source

## Upstream
- **Repository**: https://github.com/Azure-Samples/octopets
- **Commit**: da3cd3042be2c95ad69dee7af877ba1833591237
- **Vendored**: 2026-01-28

## Modifications

### 2026-01-28: Fix OutOfMemoryException in GET /api/listings/{id:int}
- **Issue**: INC0010064 - Sev3 OutOfMemoryException causing 500 errors
- **Files modified**:
  - `backend/Endpoints/ListingEndpoints.cs`
- **Changes**:
  - Removed `AReallyExpensiveOperation()` method that allocated ~1GB memory for demo/testing
  - Removed ERRORS configuration flag check from GET /{id:int} endpoint
  - Simplified endpoint to directly fetch and return listing data
- **Reason**: The memory-intensive operation was causing OutOfMemoryException under concurrent load (66 failures observed). This was a demo/test feature and not needed for production operation.

## Why Vendored
This lab uses a snapshot of Octopets for:
1. Demonstrating Azure SRE Agent capabilities with a realistic workload
2. Applying lab-specific fixes and configurations
3. Ensuring reproducibility without dependency on upstream changes

## Updating
To update this vendored copy:
1. Clone/pull latest from upstream: `git clone https://github.com/Azure-Samples/octopets.git /tmp/octopets-upstream`
2. Remove the current vendored copy (except this ORIGIN.md)
3. Copy new files from upstream
4. Reapply any lab-specific modifications documented above
5. Update the commit hash and date in this file
