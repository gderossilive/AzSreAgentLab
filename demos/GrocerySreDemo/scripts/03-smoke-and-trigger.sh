#!/usr/bin/env bash
set -euo pipefail

# Basic smoke tests + trigger supplier rate limiting.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_root="$(cd "$script_dir/.." && pwd)"
config_path="$demo_root/demo-config.json"

log_step() { echo; echo "[STEP] $*"; }
log_ok() { echo "[OK] $*"; }
log_info() { echo "[INFO] $*"; }
log_err() { echo "[ERROR] $*" >&2; }

die() { log_err "$*"; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl not found"
command -v python3 >/dev/null 2>&1 || die "python3 not found (used for JSON parsing)"
command -v az >/dev/null 2>&1 || die "Azure CLI (az) not found"

[[ -f "$config_path" ]] || die "Missing $config_path. Run scripts/01-setup-demo.sh first."

api_url="$(python3 -c "import json; print(json.load(open('$config_path'))['ApiUrl'].rstrip('/'))")"
web_url="$(python3 -c "import json; print(json.load(open('$config_path'))['WebUrl'].rstrip('/'))")"
subscription_id="$(python3 -c "import json; print(json.load(open('$config_path'))['SubscriptionId'])")"
rg_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ResourceGroupName'])")"
api_app_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ApiContainerAppName'])")"

[[ -n "$api_url" ]] || die "ApiUrl missing in demo-config.json"
[[ -n "$web_url" ]] || die "WebUrl missing in demo-config.json"

log_step "Smoke: health endpoints"
curl -fsS "$api_url/health" >/dev/null && log_ok "API /health OK"
curl -fsS "$web_url/health" >/dev/null && log_ok "Web /health OK"

log_step "Smoke: list products"
curl -fsS "$api_url/api/products" >/dev/null && log_ok "API /api/products OK"

log_step "Prep: pin API to 1 replica (demo reliability)"
az account show >/dev/null 2>&1 || die "Azure CLI not logged in. Run: az login"
az account set --subscription "$subscription_id" >/dev/null
az containerapp update -g "$rg_name" -n "$api_app_name" --min-replicas 1 --max-replicas 1 >/dev/null
log_ok "Pinned $api_app_name scale to 1 replica"

log_step "Trigger: hit inventory endpoint to induce 429s"
set +e
failures=0
for i in {1..60}; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" "$api_url/api/products/PROD001/inventory")"
  if [[ "$code" == "503" ]]; then
    log_ok "Got 503 (supplier rate limit simulated) on attempt $i"
    failures=$((failures+1))
  fi
done
set -e

log_info "Observed 503 count: $failures"
log_ok "Done"
