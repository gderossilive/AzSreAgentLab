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

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/07-create-custom-grafana-dashboard.sh [--dashboard overview|scene4] [--with-prometheus]
  ./scripts/07-create-custom-grafana-dashboard.sh --prometheus-only

Optional Prometheus (AMW) datasource:
  --with-prometheus            Create/update a Prometheus datasource that queries Azure Monitor Workspace (Managed Prometheus)
  --prometheus-only            Only create/update the Prometheus datasource (skip Loki + dashboard)
  --prometheus-datasource-name Datasource name (default: Prometheus (AMW))
  --amw-name                    Azure Monitor Workspace name (Microsoft.Monitor/accounts). Default: auto-detect first in demo RG.
  --amw-query-endpoint          Azure Monitor Workspace Prometheus query endpoint URL. Default: read from AMW properties.
  --skip-amw-role-assignment    Do not grant Monitoring Data Reader to Grafana MI on the AMW resource.

Defaults:
  --dashboard overview

Notes:
  - Requires Loki deployed as Container App 'ca-loki' (run scripts/04-deploy-loki.sh).
  - Creates/updates datasource 'Loki (grocery)' and then creates/updates the selected dashboard.
USAGE
}

dashboard_kind="overview"
with_prometheus="false"
prometheus_only="false"
prometheus_datasource_name="Prometheus (AMW)"
amw_name=""
amw_query_endpoint=""
skip_amw_role_assignment="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dashboard)
      dashboard_kind="${2:-}"; shift 2 ;;
    --with-prometheus)
      with_prometheus="true"; shift 1 ;;
    --prometheus-only)
      with_prometheus="true"; prometheus_only="true"; shift 1 ;;
    --prometheus-datasource-name)
      prometheus_datasource_name="${2:-}"; shift 2 ;;
    --amw-name)
      amw_name="${2:-}"; shift 2 ;;
    --amw-query-endpoint)
      amw_query_endpoint="${2:-}"; shift 2 ;;
    --skip-amw-role-assignment)
      skip_amw_role_assignment="true"; shift 1 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

dashboard_template=""
dashboard_title=""
if [[ "$prometheus_only" != "true" ]]; then
  case "$dashboard_kind" in
    overview)
      dashboard_template="$demo_root/grafana/grocery-sre-overview.dashboard.template.json"
      dashboard_title="Grocery App - SRE Overview (Custom)"
      ;;
    scene4)
      dashboard_template="$demo_root/grafana/grocery-sre-scene4-validate.dashboard.template.json"
      dashboard_title="Grocery App - Scene 4 (Validate in Grafana)"
      ;;
    *)
      echo "Invalid --dashboard value: $dashboard_kind" >&2
      usage
      exit 2
      ;;
  esac
fi

tmp_dir="${TMPDIR:-/tmp}/grocery-grafana"
mkdir -p "$tmp_dir"

dashboard_rendered="$tmp_dir/grocery-${dashboard_kind}.dashboard.json"
loki_ds_def="$tmp_dir/loki.datasource.json"

log_step() { echo; echo "[STEP] $*"; }
log_ok() { echo "[OK] $*"; }
log_info() { echo "[INFO] $*"; }
log_err() { echo "[ERROR] $*" >&2; }

die() { log_err "$*"; exit 1; }

command -v az >/dev/null 2>&1 || die "Azure CLI (az) not found"
command -v python3 >/dev/null 2>&1 || die "python3 not found (used for JSON parsing)"

[[ -f "$config_path" ]] || die "Missing $config_path. Run demos/GrocerySreDemo/scripts/01-setup-demo.sh first."
if [[ "$prometheus_only" != "true" ]]; then
  [[ -f "$dashboard_template" ]] || die "Missing dashboard template: $dashboard_template"

  if grep -q "__PROM_UID__" "$dashboard_template"; then
    if [[ "$with_prometheus" != "true" ]]; then
      log_info "Selected dashboard template requires Prometheus (AMW); enabling --with-prometheus automatically"
      with_prometheus="true"
    fi
  fi
fi

subscription_id="$(python3 -c "import json; print(json.load(open('$config_path'))['SubscriptionId'])")"
rg_name="$(python3 -c "import json; print(json.load(open('$config_path'))['ResourceGroupName'])")"
grafana_name="$(python3 -c "import json; print(json.load(open('$config_path'))['GrafanaName'])")"
api_containerapp_name="$(python3 -c "import json; print(json.load(open('$config_path')).get('ApiContainerAppName',''))")"

az account show >/dev/null 2>&1 || die "Azure CLI not logged in. Run: az login"
az account set --subscription "$subscription_id" >/dev/null

log_step "Ensuring Azure Managed Grafana CLI extension is available"
az extension add --name amg --upgrade --only-show-errors >/dev/null || true

if [[ "$with_prometheus" == "true" ]]; then
  if [[ -z "$amw_name" ]]; then
    log_step "Auto-detecting Azure Monitor Workspace (AMW) in $rg_name"
    amw_name="$(az resource list -g "$rg_name" --resource-type Microsoft.Monitor/accounts --query "[0].name" -o tsv)"
    [[ -n "$amw_name" ]] || die "Unable to find an Azure Monitor Workspace (Microsoft.Monitor/accounts) in $rg_name. Pass --amw-name."
  fi

  amw_id="$(az resource show -g "$rg_name" -n "$amw_name" --resource-type Microsoft.Monitor/accounts --query id -o tsv)"
  [[ -n "$amw_id" ]] || die "Unable to resolve AMW resource id for $amw_name"

  if [[ -z "$amw_query_endpoint" ]]; then
    log_step "Resolving AMW Prometheus query endpoint from AMW properties"
    amw_query_endpoint="$(az resource show -g "$rg_name" -n "$amw_name" --resource-type Microsoft.Monitor/accounts --query properties.metrics.prometheusQueryEndpoint -o tsv)"
    [[ -n "$amw_query_endpoint" ]] || die "Unable to read properties.metrics.prometheusQueryEndpoint from AMW $amw_name"
  fi
  amw_query_endpoint="${amw_query_endpoint%/}"
  log_ok "AMW query endpoint: $amw_query_endpoint"

  if [[ "$skip_amw_role_assignment" != "true" ]]; then
    log_step "Ensuring Grafana managed identity can query AMW (Monitoring Data Reader on AMW scope)"

    grafana_principal_id="$(az grafana show -g "$rg_name" -n "$grafana_name" --query identity.principalId -o tsv 2>/dev/null || true)"
    [[ -n "$grafana_principal_id" ]] || die "Unable to resolve Grafana managed identity principalId for $grafana_name"

    existing_ra="$(az role assignment list --assignee-object-id "$grafana_principal_id" --scope "$amw_id" --query "[?roleDefinitionName=='Monitoring Data Reader'] | length(@)" -o tsv 2>/dev/null || echo 0)"
    if [[ "$existing_ra" == "0" ]]; then
      az role assignment create \
        --assignee-object-id "$grafana_principal_id" \
        --assignee-principal-type ServicePrincipal \
        --role "Monitoring Data Reader" \
        --scope "$amw_id" \
        --only-show-errors >/dev/null
      log_ok "Granted Monitoring Data Reader on AMW to Grafana MI"
    else
      log_ok "Role assignment already present"
    fi
  else
    log_info "Skipping role assignment (--skip-amw-role-assignment)"
  fi

  log_step "Creating/updating Prometheus datasource in Managed Grafana"
  prom_ds_def="$tmp_dir/prometheus-amw.datasource.json"
  cat >"$prom_ds_def" <<JSON
{
  "name": "${prometheus_datasource_name}",
  "type": "prometheus",
  "access": "proxy",
  "url": "${amw_query_endpoint}",
  "isDefault": false,
  "jsonData": {
    "httpMethod": "POST",
    "azureAuthType": "msi",
    "azureCredentials": {
      "authType": "msi"
    },
    "timeInterval": "15s"
  }
}
JSON

  prom_uid="$(az grafana data-source list -g "$rg_name" -n "$grafana_name" --query "[?name=='${prometheus_datasource_name}'].uid | [0]" -o tsv)"
  if [[ -z "$prom_uid" ]]; then
    az grafana data-source create -g "$rg_name" -n "$grafana_name" --definition "@$prom_ds_def" --only-show-errors >/dev/null
    prom_uid="$(az grafana data-source list -g "$rg_name" -n "$grafana_name" --query "[?name=='${prometheus_datasource_name}'].uid | [0]" -o tsv)"
    [[ -n "$prom_uid" ]] || die "Failed to resolve Prometheus datasource uid after create"
    log_ok "Prometheus datasource uid: $prom_uid"
  else
    az grafana data-source update -g "$rg_name" -n "$grafana_name" --data-source "$prom_uid" --definition "@$prom_ds_def" --only-show-errors >/dev/null
    log_ok "Prometheus datasource uid: $prom_uid"
  fi

  [[ -n "$prom_uid" ]] || die "Prometheus datasource uid is empty"
fi

if [[ "$prometheus_only" == "true" ]]; then
  log_ok "Prometheus datasource created/updated"
  endpoint="$(az grafana show -g "$rg_name" -n "$grafana_name" --query properties.endpoint -o tsv 2>/dev/null || true)"
  if [[ -n "$endpoint" ]]; then
    log_info "Grafana endpoint: $endpoint"
    log_info "Open Grafana → Connections → Data sources → '${prometheus_datasource_name}'"
  fi
  exit 0
fi

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

azmon_uid=""
if grep -q "__AZMON_UID__" "$dashboard_template"; then
  log_step "Resolving Azure Monitor datasource uid in Managed Grafana"
  azmon_uid="$(az grafana data-source list -g "$rg_name" -n "$grafana_name" --query "[?type=='grafana-azure-monitor-datasource'].uid | [0]" -o tsv)"
  [[ -n "$azmon_uid" ]] || die "Azure Monitor datasource not found in Managed Grafana (expected type grafana-azure-monitor-datasource)"
  log_ok "Azure Monitor datasource uid: $azmon_uid"

  if [[ -z "$api_containerapp_name" ]]; then
    die "demo-config.json is missing ApiContainerAppName (needed for Azure Monitor panels). Re-run demos/GrocerySreDemo/scripts/01-setup-demo.sh"
  fi
  log_ok "API Container App: $api_containerapp_name"
fi

prom_uid_for_dashboard="${prom_uid:-}"
if grep -q "__PROM_UID__" "$dashboard_template"; then
  [[ -n "$prom_uid_for_dashboard" ]] || die "Dashboard template requires Prometheus datasource uid (__PROM_UID__), but Prometheus datasource was not created. Ensure AMW exists in the demo resource group, or pass --with-prometheus and fix AMW detection."
fi

log_step "Rendering dashboard definition"
python3 - "$dashboard_template" "$dashboard_rendered" "$loki_uid" "$azmon_uid" "$prom_uid_for_dashboard" "$subscription_id" "$rg_name" "$api_containerapp_name" <<'PY'
import json
import sys

src, dst = sys.argv[1], sys.argv[2]
loki_uid, azmon_uid = sys.argv[3], sys.argv[4]
prom_uid = sys.argv[5]
subscription_id, rg_name, api_containerapp_name = sys.argv[6], sys.argv[7], sys.argv[8]

with open(src, 'r', encoding='utf-8') as f:
    data = json.load(f)

serialized = json.dumps(data)
serialized = serialized.replace('__LOKI_UID__', loki_uid)
serialized = serialized.replace('__AZMON_UID__', azmon_uid)
serialized = serialized.replace('__PROM_UID__', prom_uid)
serialized = serialized.replace('__SUBSCRIPTION_ID__', subscription_id)
serialized = serialized.replace('__RESOURCE_GROUP__', rg_name)
serialized = serialized.replace('__API_CONTAINERAPP_NAME__', api_containerapp_name)

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
