#!/usr/bin/env bash
set -euo pipefail

# Build and deploy Grocery API + Web using ACR remote builds.
# Requires demo-config.json created by 01-setup-demo.sh.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_root="$(cd "$script_dir/.." && pwd)"
repo_root="$(cd "$demo_root/../.." && pwd)"
config_path="$demo_root/demo-config.json"

log_step() { echo; echo "[STEP] $*"; }
log_ok() { echo "[OK] $*"; }
log_info() { echo "[INFO] $*"; }
log_err() { echo "[ERROR] $*" >&2; }

die() { log_err "$*"; exit 1; }

command -v az >/dev/null 2>&1 || die "Azure CLI (az) not found"
command -v python3 >/dev/null 2>&1 || die "python3 not found (used for JSON parsing)"

[[ -f "$config_path" ]] || die "Missing $config_path. Run scripts/01-setup-demo.sh first."

subscription_id="$(python3 -c "import json; print(json.load(open('$config_path'))['SubscriptionId'])")"
rg_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ResourceGroupName'])")"
acr_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ContainerRegistryName'])")"
acr_login="$(python3 -c "import json; print(json.load(open('$config_path'))['ContainerRegistryLoginServer'])")"
api_app="$(python3 -c "import json; print(json.load(open('$config_path'))['ApiContainerAppName'])")"
web_app="$(python3 -c "import json; print(json.load(open('$config_path'))['WebContainerAppName'])")"

az account show >/dev/null 2>&1 || die "Azure CLI not logged in. Run: az login"
az account set --subscription "$subscription_id" >/dev/null

api_dockerfile="$demo_root/docker/api.Dockerfile"
web_dockerfile="$demo_root/docker/web.Dockerfile"
[[ -f "$api_dockerfile" ]] || die "API Dockerfile not found: $api_dockerfile"
[[ -f "$web_dockerfile" ]] || die "Web Dockerfile not found: $web_dockerfile"

tag="$(date -u +%Y%m%d%H%M%S)"

log_step "Building images in ACR ($acr_name) tag=$tag"
az acr build -r "$acr_name" -t "grocery-api:$tag" -f "$api_dockerfile" "$repo_root"
log_ok "Built grocery-api:$tag"
az acr build -r "$acr_name" -t "grocery-web:$tag" -f "$web_dockerfile" "$repo_root"
log_ok "Built grocery-web:$tag"

api_image="$acr_login/grocery-api:$tag"
web_image="$acr_login/grocery-web:$tag"

log_step "Updating Container Apps images"
az containerapp update -g "$rg_name" -n "$api_app" --image "$api_image" >/dev/null
log_ok "Updated $api_app -> $api_image"

az containerapp update -g "$rg_name" -n "$web_app" --image "$web_image" >/dev/null
log_ok "Updated $web_app -> $web_image"

log_step "Refreshing URLs (in case revisions changed)"
api_url="$(az containerapp show -g "$rg_name" -n "$api_app" --query properties.configuration.ingress.fqdn -o tsv)"
web_url="$(az containerapp show -g "$rg_name" -n "$web_app" --query properties.configuration.ingress.fqdn -o tsv)"

python3 - "$config_path" "$tag" "$api_url" "$web_url" <<'PY'
import json
import sys

path, tag, api_fqdn, web_fqdn = sys.argv[1:]
j = json.load(open(path, encoding='utf-8'))
j['LastImageTag'] = tag
j['ApiUrl'] = f"https://{api_fqdn}" if api_fqdn else j.get('ApiUrl','')
j['WebUrl'] = f"https://{web_fqdn}" if web_fqdn else j.get('WebUrl','')
with open(path, 'w', encoding='utf-8') as f:
  json.dump(j, f, indent=2)
  f.write('\n')
print('Updated demo-config.json with LastImageTag and refreshed URLs')
PY

log_ok "Build+deploy complete"
