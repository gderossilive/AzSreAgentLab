#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Vendors an external git repository into ./external/<name> as a modifiable folder (like external/octopets).

This:
  - clones to a temp dir
  - checks out a pinned ref (branch/tag/commit)
  - removes the inner .git folder
  - writes external/<name>/ORIGIN.md

Usage:
  scripts/11-vendor-external-repo.sh --repo-url <url> --name <folder-name> [--ref <ref>] [--cloned <date>] [--purpose <text>]

Examples:
  scripts/11-vendor-external-repo.sh --repo-url https://github.com/OWNER/REPO.git --name repo --ref v1.2.3
  scripts/11-vendor-external-repo.sh --repo-url https://github.com/OWNER/REPO.git --name repo --ref <commit-sha>

Notes:
  - If external/<name> already exists, this script exits (no overwrite).
  - The resulting folder is *not* a git repo (no nested .git).
EOF
}

REPO_URL=""
NAME=""
REF=""
CLONED=""
PURPOSE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-url)
      REPO_URL="${2:-}"; shift 2 ;;
    --name)
      NAME="${2:-}"; shift 2 ;;
    --ref)
      REF="${2:-}"; shift 2 ;;
    --cloned)
      CLONED="${2:-}"; shift 2 ;;
    --purpose)
      PURPOSE="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$REPO_URL" || -z "$NAME" ]]; then
  echo "Missing required args." >&2
  usage
  exit 2
fi

DEST_DIR="external/${NAME}"

if [[ -e "$DEST_DIR" ]]; then
  echo "$DEST_DIR already exists; refusing to overwrite" >&2
  exit 1
fi

mkdir -p external

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Cloning $REPO_URL to temp dir..."
git clone --quiet "$REPO_URL" "$TMP_DIR/repo"

pushd "$TMP_DIR/repo" >/dev/null

if [[ -n "$REF" ]]; then
  echo "Checking out ref: $REF"
  git checkout --quiet "$REF"
else
  REF="$(git rev-parse HEAD)"
fi

ORIGIN_URL="$(git remote get-url origin || true)"

echo "Removing nested .git to vendor as plain folder..."
rm -rf .git

popd >/dev/null

mv "$TMP_DIR/repo" "$DEST_DIR"

if [[ -z "$CLONED" ]]; then
  CLONED="$(date +%Y-%m-%d)"
fi

if [[ -z "$PURPOSE" ]]; then
  PURPOSE="Vendored for AzSreAgentLab demos (modifiable copy)"
fi

cat >"$DEST_DIR/ORIGIN.md" <<EOF
# Original Source

This is a modified copy of an external repository.

**Original Repository**: ${ORIGIN_URL:-$REPO_URL}  
**Vendored (pinned ref)**: ${REF}  
**Cloned**: ${CLONED}  
**Purpose**: ${PURPOSE}

## Notes

- This folder is vendored into AzSreAgentLab as a normal directory (no nested .git).
- Update this file if you make significant modifications.
EOF

echo "Done. Vendored into $DEST_DIR"
