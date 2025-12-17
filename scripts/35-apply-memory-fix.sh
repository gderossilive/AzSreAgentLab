#!/usr/bin/env bash
set -euo pipefail

# Apply the memory fix patch to the octopets repository
#
# Usage:
#   scripts/35-apply-memory-fix.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OCTOPETS_DIR="$REPO_ROOT/external/octopets"
PATCH_FILE="$REPO_ROOT/demo/octopets-memory-fix.patch"

if [[ ! -d "$OCTOPETS_DIR" ]]; then
  echo "ERROR: Octopets directory not found at $OCTOPETS_DIR" >&2
  echo "Run scripts/10-clone-repos.sh first" >&2
  exit 1
fi

if [[ ! -f "$PATCH_FILE" ]]; then
  echo "ERROR: Patch file not found at $PATCH_FILE" >&2
  exit 1
fi

echo "Applying memory fix patch to octopets..."
cd "$OCTOPETS_DIR"

# Check if patch is already applied
if git apply --check "$PATCH_FILE" 2>/dev/null; then
  git apply "$PATCH_FILE"
  echo "✅ Memory fix patch applied successfully!"
else
  echo "⚠️  Patch may already be applied or conflicts detected"
  echo "Current git status:"
  git status --short
  
  # Try to apply anyway with 3-way merge
  if git apply --3way "$PATCH_FILE" 2>/dev/null; then
    echo "✅ Patch applied with 3-way merge"
  else
    echo "❌ Failed to apply patch. Manual intervention required."
    echo "See demo/OCTOPETS_MEMORY_FIX.md for manual instructions"
    exit 1
  fi
fi

echo ""
echo "Changes applied:"
echo "  - Removed AReallyExpensiveOperation() memory leak"
echo "  - Removed ERRORS flag from production mode"
echo "  - Added /health/live and /health/ready endpoints"
echo ""
echo "Next steps:"
echo "  1. Review changes: cd external/octopets && git diff"
echo "  2. Rebuild and deploy: scripts/31-deploy-octopets-containers.sh"
