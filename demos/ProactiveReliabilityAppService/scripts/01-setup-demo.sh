#!/usr/bin/env bash
set -euo pipefail

# Proactive Reliability demo setup (App Service slot swap) - Bash version
#
# Deploys:
# - App Service + staging slot + App Insights + activity log alert (Bicep)
# - GOOD app build to production
# - BAD app build to staging
# - Writes demo-config.json (no secrets)

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_root="$(cd "$script_dir/.." && pwd)"
repo_root="$(cd "$demo_root/../.." && pwd)"
infra_dir="$demo_root/infrastructure"
config_path="$demo_root/demo-config.json"

upstream_root="$repo_root/external/sre-agent/samples/proactive-reliability"
app_path="$upstream_root/SREPerfDemo"
controller_path="$app_path/Controllers/ProductsController.cs"

log_step() { echo; echo "[STEP] $*"; }
log_ok() { echo "[OK] $*"; }
log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*"; }
log_err() { echo "[ERROR] $*" >&2; }

die() { log_err "$*"; exit 1; }

usage() {
  cat <<EOF
Usage: $0 [--resource-group <name>] [--app-service-name <name>] [--location <region>] [--subscription-id <guid>] [--skip-env-file] [--env-file <path>]

Defaults:
  - subscription-id: AZURE_SUBSCRIPTION_ID (from .env) or current az account
  - location:        AZURE_LOCATION (from .env) or swedencentral
  - resource-group:  PROACTIVE_DEMO_RG_NAME (from .env) or rg-sre-proactive-demo
  - app-service:     PROACTIVE_DEMO_APP_SERVICE_NAME (from .env) or auto-generated
EOF
}

# -----------------------------
# Parse args
# -----------------------------
resource_group=""
app_service_name=""
location=""
subscription_id=""
skip_env_file="false"
env_file_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group|-g)
      resource_group="${2:-}"; shift 2 ;;
    --app-service-name|-n)
      app_service_name="${2:-}"; shift 2 ;;
    --location|-l)
      location="${2:-}"; shift 2 ;;
    --subscription-id|-s)
      subscription_id="${2:-}"; shift 2 ;;
    --env-file)
      env_file_path="${2:-}"; shift 2 ;;
    --skip-env-file)
      skip_env_file="true"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "Unknown argument: $1" ;;
  esac
done

# -----------------------------
# Load .env (optional)
# -----------------------------
import_dotenv() {
  local path="$1"
  [[ -f "$path" ]] || return 0

  log_info "Loading env file: $path"

  # shellcheck disable=SC2162
  while IFS= read line || [[ -n "$line" ]]; do
    line="${line%%\r}"
    [[ -z "${line// }" ]] && continue
    [[ "${line:0:1}" == "#" ]] && continue

    if [[ "$line" != *"="* ]]; then
      continue
    fi

    local name="${line%%=*}"
    local value="${line#*=}"

    name="$(echo "$name" | xargs)"
    value="$(echo "$value" | xargs)"

    # Strip surrounding quotes
    if [[ "$value" =~ ^\".*\"$ ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" =~ ^\'.*\'$ ]]; then
      value="${value:1:${#value}-2}"
    fi

    export "$name"="$value"
  done <"$path"
}

if [[ "$skip_env_file" != "true" ]]; then
  if [[ -z "$env_file_path" ]]; then
    env_file_path="$repo_root/.env"
  fi
  import_dotenv "$env_file_path"
fi

# Defaults from env
subscription_id="${subscription_id:-${AZURE_SUBSCRIPTION_ID:-}}"
location="${location:-${AZURE_LOCATION:-swedencentral}}"
resource_group="${resource_group:-${PROACTIVE_DEMO_RG_NAME:-rg-sre-proactive-demo}}"
app_service_name="${app_service_name:-${PROACTIVE_DEMO_APP_SERVICE_NAME:-}}"

# If not set, reuse the last generated app name (avoids creating a new app every run).
if [[ -z "$app_service_name" && -f "$config_path" ]]; then
  app_service_name="$(python3 - "$config_path" <<'PY' 2>/dev/null
import json
import sys

path = sys.argv[1]
try:
  j = json.load(open(path))
  print(j.get('AppServiceName', ''))
except Exception:
  print('')
PY
)"
fi

# Generate app service name if missing
if [[ -z "$app_service_name" ]]; then
  user="${USER:-demo}"
  suffix="$(( (RANDOM % 90000) + 10000 ))"
  app_service_name="sreproactive-${user,,}-${suffix}"
  # Keep only allowed chars (conservative)
  app_service_name="$(echo "$app_service_name" | tr -cd 'a-z0-9-')"
  app_service_name="${app_service_name:0:60}"
  log_info "Generated App Service name: $app_service_name"
fi

# -----------------------------
# Preconditions
# -----------------------------
command -v az >/dev/null 2>&1 || die "Azure CLI (az) not found"
command -v dotnet >/dev/null 2>&1 || die ".NET SDK (dotnet) not found"
command -v python3 >/dev/null 2>&1 || die "python3 not found (used for JSON + zip)"

[[ -d "$app_path" ]] || die "Upstream app path not found: $app_path"
[[ -f "$controller_path" ]] || die "Controller file not found: $controller_path"

# -----------------------------
# Azure subscription selection
# -----------------------------
log_step "Checking Azure subscription"

if ! az account show >/dev/null 2>&1; then
  die "Azure CLI not logged in. Run: az login"
fi

if [[ -n "$subscription_id" ]]; then
  log_info "Setting subscription: $subscription_id"
  az account set --subscription "$subscription_id" >/dev/null
else
  subscription_id="$(az account show --query id -o tsv)"
  log_info "Using current subscription: $subscription_id"
fi

# -----------------------------
# Deploy infra
# -----------------------------
log_step "Creating resource group: $resource_group"
az group create --name "$resource_group" --location "$location" --output none >/dev/null
log_ok "Resource group ready"

log_step "Deploying infrastructure (App Service, App Insights, slot swap alert)"
outputs_json="$(az deployment group create \
  --resource-group "$resource_group" \
  --template-file "$infra_dir/main.bicep" \
  --parameters appServiceName="$app_service_name" location="$location" \
  --query properties.outputs \
  --output json)"

prod_url="$(python3 -c "import json,sys; j=json.load(sys.stdin); print(j['appServiceUrl']['value'])" <<<"$outputs_json")"

staging_url="$(python3 -c "import json,sys; j=json.load(sys.stdin); print(j['stagingUrl']['value'])" <<<"$outputs_json")"

app_insights_name="$(python3 -c "import json,sys; j=json.load(sys.stdin); print(j['applicationInsightsName']['value'])" <<<"$outputs_json")"

if [[ -z "$prod_url" || -z "$staging_url" || -z "$app_insights_name" ]]; then
  die "Deployment outputs were missing/empty. Check 'az deployment group create' output in the portal or rerun with a fixed app name."
fi

log_ok "Infrastructure deployed"
log_info "  Production URL: $prod_url"
log_info "  Staging URL: $staging_url"
log_info "  App Insights: $app_insights_name"

# -----------------------------
# Build & deploy GOOD/BAD
# -----------------------------
original_controller_tmp="$(mktemp)"
cp "$controller_path" "$original_controller_tmp"

revert_controller() {
  if [[ -f "$original_controller_tmp" ]]; then
    cp "$original_controller_tmp" "$controller_path" || true
    rm -f "$original_controller_tmp" || true
  fi
}
trap revert_controller EXIT

set_slow_flag() {
  local enabled="$1" # true|false
  python3 - "$enabled" "$controller_path" <<'PY'
from pathlib import Path
import re
import sys

enabled = sys.argv[1]
path = Path(sys.argv[2])
text = path.read_text(encoding='utf-8')
pattern = r"private const bool EnableSlowEndpoints = (true|false);.*"
replacement = f"private const bool EnableSlowEndpoints = {enabled};  // {'BAD: Slow version' if enabled=='true' else 'GOOD: Fast version'}"
new_text, count = re.subn(pattern, replacement, text)
if count == 0:
    raise SystemExit('Could not find EnableSlowEndpoints constant to update')
path.write_text(new_text, encoding='utf-8')
PY
}

zip_dir() {
  local dir="$1"
  local out_zip="$2"
  python3 - <<PY
import os
import zipfile
from pathlib import Path
src = Path(r"$dir")
out = Path(r"$out_zip")
if out.exists():
    out.unlink()
with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    for p in src.rglob('*'):
        if p.is_file():
            z.write(p, p.relative_to(src))
print(str(out))
PY
}

log_step "Building + deploying GOOD (fast) version to production"
set_slow_flag false
(
  cd "$app_path"
  rm -rf ./publish-good || true
  dotnet publish -c Release -o ./publish-good --nologo -v q
  good_zip="$(zip_dir "$app_path/publish-good" "$app_path/good-app.zip")"
  az webapp deploy --resource-group "$resource_group" --name "$app_service_name" --src-path "$good_zip" --type zip --output none 2>/dev/null
)
log_ok "GOOD version deployed to production"

log_step "Building + deploying BAD (slow) version to staging"
set_slow_flag true
(
  cd "$app_path"
  rm -rf ./publish-bad || true
  dotnet publish -c Release -o ./publish-bad --nologo -v q
  bad_zip="$(zip_dir "$app_path/publish-bad" "$app_path/bad-app.zip")"
  az webapp deploy --resource-group "$resource_group" --name "$app_service_name" --slot staging --src-path "$bad_zip" --type zip --output none 2>/dev/null
)
log_ok "BAD version deployed to staging"

# Immediately revert file back (even though trap also does this)
revert_controller
trap - EXIT

# -----------------------------
# Write demo-config.json
# -----------------------------
log_step "Writing demo-config.json"
cat >"$config_path" <<EOF
{
  "ResourceGroupName": "${resource_group}",
  "AppServiceName": "${app_service_name}",
  "Location": "${location}",
  "SubscriptionId": "${subscription_id}",
  "ProductionUrl": "${prod_url}",
  "StagingUrl": "${staging_url}",
  "ApplicationInsightsName": "${app_insights_name}"
}
EOF
log_ok "Wrote config: $config_path"

# -----------------------------
# Sanity check
# -----------------------------
log_step "Sanity check (health endpoints)"
sleep 20

if command -v curl >/dev/null 2>&1; then
  if curl -fsS --max-time 30 "$prod_url/health" >/dev/null; then
    log_ok "Production health endpoint reachable"
  else
    log_warn "Production health check failed (may still be starting)"
  fi

  if curl -fsS --max-time 30 "$staging_url/health" >/dev/null; then
    log_ok "Staging health endpoint reachable"
  else
    log_warn "Staging health check failed (may still be starting)"
  fi
else
  log_warn "curl not found; skipping HTTP checks"
fi

log_ok "Setup complete. Next: deploy SRE Agent (same RG) and configure subagents/triggers."
