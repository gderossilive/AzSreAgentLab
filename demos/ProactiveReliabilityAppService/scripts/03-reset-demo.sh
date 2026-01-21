#!/usr/bin/env bash
set -euo pipefail

# Proactive Reliability demo reset helper
#
# Goal: return to the "baseline" state created by 01-setup-demo.sh:
# - GOOD build in production
# - BAD build in staging
#
# This script is conservative by default: it probes production vs staging and
# only performs a slot swap when production looks worse than staging.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_root="$(cd "$script_dir/.." && pwd)"
config_path="$demo_root/demo-config.json"

log_step() { echo; echo "[STEP] $*"; }
log_ok() { echo "[OK] $*"; }
log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*"; }
log_err() { echo "[ERROR] $*" >&2; }

die() { log_err "$*"; exit 1; }

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --probe-path <path>     Path to probe (default: /api/products)
  --samples <n>           Number of samples per slot (default: 3)
  --force-swap            Always swap staging <-> production (dangerous)
  --restart               Restart production and staging after swap/check
  --dry-run               Print what would happen, do not mutate Azure
  -h, --help              Show help

Env overrides:
  PROACTIVE_DEMO_PROBE_PATH  Same as --probe-path
EOF
}

probe_path="${PROACTIVE_DEMO_PROBE_PATH:-/api/products}"
samples=3
force_swap=false
restart_after=false
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --probe-path)
      probe_path="${2:-}"; shift 2 ;;
    --samples)
      samples="${2:-}"; shift 2 ;;
    --force-swap)
      force_swap=true; shift ;;
    --restart)
      restart_after=true; shift ;;
    --dry-run)
      dry_run=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "Unknown argument: $1" ;;
  esac
done

command -v az >/dev/null 2>&1 || die "Azure CLI (az) not found"
command -v python3 >/dev/null 2>&1 || die "python3 not found (used for JSON parsing)"
command -v curl >/dev/null 2>&1 || die "curl not found"

[[ -f "$config_path" ]] || die "demo-config.json not found at $config_path. Run ./scripts/01-setup-demo.sh first."

resource_group="$(python3 - <<PY
import json
j=json.load(open(r"$config_path"))
print(j['ResourceGroupName'])
PY
)"
app_service_name="$(python3 - <<PY
import json
j=json.load(open(r"$config_path"))
print(j['AppServiceName'])
PY
)"
prod_url="$(python3 - <<PY
import json
j=json.load(open(r"$config_path"))
print(j['ProductionUrl'].rstrip('/'))
PY
)"
staging_url="$(python3 - <<PY
import json
j=json.load(open(r"$config_path"))
print(j['StagingUrl'].rstrip('/'))
PY
)"

banner() {
  local title="$1"
  echo
  echo "============================================================"
  echo "  $title"
  echo "============================================================"
  echo
}

to_ms() {
  python3 -c 'import sys
try:
  print(int(round(float(sys.argv[1]) * 1000)))
except Exception:
  sys.exit(2)
' "$1"
}

# Prints: "<http_code> <ms>" (ms is blank if time_total not parseable)
measure_http() {
  local url="$1"
  local max_time_s="$2"

  local out
  out="$(curl -sS --max-time "$max_time_s" -o /tmp/resp.$$ -w '%{http_code} %{time_total}' "$url" || true)"

  local http_code="${out%% *}"
  local time_total="${out#* }"

  local ms=""
  if [[ "$time_total" != "$http_code" && -n "$time_total" ]]; then
    ms="$(to_ms "$time_total" 2>/dev/null || true)"
  fi

  printf '%s %s' "$http_code" "$ms"
}

sample_slot_ms() {
  local base_url="$1"
  local slot_label="$2"

  # Warm up (best-effort)
  curl -fsS --max-time 30 "$base_url$probe_path" >/dev/null 2>&1 || true
  sleep 0.3

  local measurements=()

  for ((i=1; i<=samples; i++)); do
    local m
    m="$(measure_http "$base_url$probe_path" 60)"

    local code="${m%% *}"
    local ms="${m#* }"

    if [[ "$code" == "200" && "$ms" =~ ^[0-9]+$ ]]; then
      measurements+=("$ms")
      log_info "$slot_label sample $i/$samples: ${ms}ms" >&2
    else
      local body_snip
      body_snip="$(head -c 180 /tmp/resp.$$ | tr -d '\n' || true)"
      log_warn "$slot_label sample $i/$samples: HTTP=$code (${ms:-n/a}ms) body='${body_snip}'" >&2
    fi

    sleep 0.3
  done

  rm -f /tmp/resp.$$ >/dev/null 2>&1 || true

  if [[ ${#measurements[@]} -eq 0 ]]; then
    echo ""
    return 1
  fi

  # Use median to reduce outlier impact
  printf '%s\n' "${measurements[@]}" | sort -n | python3 -c 'import sys
vals=[int(x) for x in sys.stdin.read().strip().split() if x.strip()]
if not vals:
  raise SystemExit(1)
vals.sort()
mid=len(vals)//2
if len(vals)%2==1:
  print(vals[mid])
else:
  print((vals[mid-1]+vals[mid])//2)
'
}

should_swap_back() {
  local prod_ms="$1"
  local staging_ms="$2"

  # Swap back if production appears materially worse than staging.
  # Heuristics:
  # - prod > staging + 500ms, OR
  # - prod >= 1.3x staging (when staging is reasonably fast)

  if (( prod_ms > staging_ms + 500 )); then
    return 0
  fi

  if (( staging_ms > 0 )); then
    # integer math: prod*10 >= staging*13 means prod >= 1.3x staging
    if (( prod_ms * 10 >= staging_ms * 13 )); then
      return 0
    fi
  fi

  return 1
}

banner "RESET PROACTIVE RELIABILITY DEMO"
echo "  App Service:    $app_service_name"
echo "  Resource Group: $resource_group"
echo "  Production:     $prod_url"
echo "  Staging:        $staging_url"
echo "  Probe Path:     $probe_path"
echo "  Samples:        $samples"
echo

log_step "Probing production and staging"
prod_ms="$(sample_slot_ms "$prod_url" "Production" || true)"
staging_ms="$(sample_slot_ms "$staging_url" "Staging" || true)"

if [[ -z "$prod_ms" || -z "$staging_ms" ]]; then
  log_warn "Could not get reliable timing samples from one or both slots."
  if [[ "$force_swap" != "true" ]]; then
    die "Re-run with --force-swap to swap anyway, or fix the endpoint/probe-path."
  fi
fi

if [[ "$force_swap" == "true" ]]; then
  log_warn "--force-swap enabled: will swap staging <-> production regardless of probe results."
  do_swap=true
else
  if should_swap_back "$prod_ms" "$staging_ms"; then
    log_warn "Production (${prod_ms}ms) looks worse than staging (${staging_ms}ms): will swap back."
    do_swap=true
  else
    log_ok "Production (${prod_ms}ms) does not look worse than staging (${staging_ms}ms): no swap needed."
    do_swap=false
  fi
fi

if [[ "$do_swap" == "true" ]]; then
  log_step "Swapping staging -> production"
  if [[ "$dry_run" == "true" ]]; then
    log_info "Dry run: would execute slot swap now."
  else
    az webapp deployment slot swap \
      --resource-group "$resource_group" \
      --name "$app_service_name" \
      --slot staging \
      --target-slot production \
      --output none
    log_ok "Swap complete."
  fi
else
  log_info "No swap performed."
fi

if [[ "$restart_after" == "true" ]]; then
  log_step "Restarting production and staging"
  if [[ "$dry_run" == "true" ]]; then
    log_info "Dry run: would restart production and staging."
  else
    az webapp restart -g "$resource_group" -n "$app_service_name" --output none
    az webapp restart -g "$resource_group" -n "$app_service_name" --slot staging --output none
    log_ok "Restart complete."
  fi
fi

log_ok "Reset complete."