#!/usr/bin/env bash
set -euo pipefail

# Create (or update) a custom Grocery dashboard in Azure Managed Grafana.
# - Ensures a Loki datasource exists (pointing at ca-loki)
# - Creates/updates a custom dashboard using that Loki datasource
#
# No secrets are written.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_root="$(cd "$script_dir/.." && pwd)"
config_path="$demo_root/demo-config.json"

dashboard_template="$demo_root/grafana/grocery-sre-overview.dashboard.template.json"
dashboard_title="Grocery App - SRE Overview (Custom)"

tmp_dir="${TMPDIR:-/tmp}/grocery-grafana"
mkdir -p "$tmp_dir"

dashboard_rendered="$tmp_dir/grocery-sre-overview.dashboard.json"
loki_ds_def="$tmp_dir/loki.datasource.json"

log_step() { echo; echo "[STEP] $*"; }
log_ok() { echo "[OK] $*"; }
log_info() { echo "[INFO] $*"; }
log_err() { echo "[ERROR] $*" >&2; }

die() { log_err "$*"; exit 1; }

command -v az >/dev/null 2>&1 || die "Azure CLI (az) not found"
command -v python3 >/dev/null 2>&1 || die "python3 not found (used for JSON parsing)"

[[ -f "$config_path" ]] || die "Missing $config_path. Run demos/GrocerySreDemo/scripts/01-setup-demo.sh first."
[[ -f "$dashboard_template" ]] || die "Missing dashboard template: $dashboard_template"

subscription_id="$(python3 -c "import json; print(json.load(open('$config_path'))['SubscriptionId'])")"
rg_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ResourceGroupName'])")"
grafana_name="$(python3 -c "import json; print(json.load(open('$config_path'))['GrafanaName'])")"

az account show >/dev/null 2>&1 || die "Azure CLI not logged in. Run: az login"
az account set --subscription "$subscription_id" >/dev/null

log_step "Ensuring Azure Managed Grafana CLI extension is available"
az extension add --name amg --upgrade --only-show-errors >/dev/null || true

log_step "Resolving Loki endpoint (Container App ca-loki)"
if ! az containerapp show -g "$rg_name" -n "ca-loki" >/dev/null 2>&1; then
  die "Loki is not deployed (missing Container App 'ca-loki'). Run demos/GrocerySreDemo/scripts/04-deploy-loki.sh first."
fi
loki_fqdn="$(az containerapp show -g "$rg_name" -n "ca-loki" --query properties.configuration.ingress.fqdn -o tsv)"
[[ -n "$loki_fqdn" ]] || die "Unable to read Loki FQDN from ca-loki"
loki_url="https://${loki_fqdn}"
log_ok "Loki URL: $loki_url"

log_step "Creating/updating Loki datasource in Managed Grafana"
cat >"$loki_ds_def" <<JSON
{
  "name": "Loki (grocery)",
  "type": "loki",
  "access": "proxy",
  "url": "${loki_url}",
  "isDefault": false,
  "jsonData": {}
}
JSON

loki_uid="$(az grafana data-source list -g "$rg_name" -n "$grafana_name" --query "[?name=='Loki (grocery)'].uid | [0]" -o tsv)"
if [[ -z "$loki_uid" ]]; then
  az grafana data-source create -g "$rg_name" -n "$grafana_name" --definition "@$loki_ds_def" --only-show-errors >/dev/null
  loki_uid="$(az grafana data-source list -g "$rg_name" -n "$grafana_name" --query "[?name=='Loki (grocery)'].uid | [0]" -o tsv)"
else
  az grafana data-source update -g "$rg_name" -n "$grafana_name" --data-source "$loki_uid" --definition "@$loki_ds_def" --only-show-errors >/dev/null
fi

[[ -n "$loki_uid" ]] || die "Failed to resolve Loki datasource uid after create/update"
log_ok "Loki datasource uid: $loki_uid"

log_step "Rendering dashboard definition"
python3 - "$dashboard_template" "$dashboard_rendered" "$loki_uid" <<'PY'
import json
import sys

src, dst, uid = sys.argv[1], sys.argv[2], sys.argv[3]

with open(src, 'r', encoding='utf-8') as f:
    data = json.load(f)

serialized = json.dumps(data)
serialized = serialized.replace('__LOKI_UID__', uid)

with open(dst, 'w', encoding='utf-8') as f:
    f.write(json.dumps(json.loads(serialized), indent=2))
    f.write('\n')
PY

log_step "Creating/updating dashboard in Managed Grafana"
existing_dashboard_uid="$(az grafana dashboard list -g "$rg_name" -n "$grafana_name" --query "[?title=='${dashboard_title}'].uid | [0]" -o tsv)"
if [[ -z "$existing_dashboard_uid" ]]; then
  az grafana dashboard create -g "$rg_name" -n "$grafana_name" --definition "@$dashboard_rendered" --only-show-errors >/dev/null
else
  existing_json="$tmp_dir/existing-dashboard.json"
  az grafana dashboard show -g "$rg_name" -n "$grafana_name" --dashboard "$existing_dashboard_uid" -o json >"$existing_json"

  python3 - "$existing_json" "$dashboard_rendered" <<'PY'
import json
import sys

existing_path, rendered_path = sys.argv[1], sys.argv[2]

with open(existing_path, 'r', encoding='utf-8') as f:
    existing = json.load(f)

with open(rendered_path, 'r', encoding='utf-8') as f:
    new_def = json.load(f)

existing_dashboard = existing.get('dashboard') or {}
new_dashboard = new_def.get('dashboard') or {}

# Grafana requires id/uid/version on update.
for key in ('id', 'uid', 'version'):
    if key in existing_dashboard:
        new_dashboard[key] = existing_dashboard[key]

new_def['dashboard'] = new_dashboard
new_def['overwrite'] = True

with open(rendered_path, 'w', encoding='utf-8') as f:
    json.dump(new_def, f, indent=2)
    f.write('\n')
PY

  az grafana dashboard update -g "$rg_name" -n "$grafana_name" --definition "@$dashboard_rendered" --only-show-errors >/dev/null
fi

endpoint="$(az grafana show -g "$rg_name" -n "$grafana_name" --query properties.endpoint -o tsv 2>/dev/null || true)"
log_ok "Dashboard created/updated"
if [[ -n "$endpoint" ]]; then
  log_info "Grafana endpoint: $endpoint"
  log_info "Open Grafana \u2192 Dashboards \u2192 '$dashboard_title'"
fi
