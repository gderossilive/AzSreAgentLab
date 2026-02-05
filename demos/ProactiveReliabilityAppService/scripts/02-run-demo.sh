#!/usr/bin/env bash
set -euo pipefail

# Proactive Reliability demo runner (App Service slot swap) - Bash version
#
# 1) Reads demo-config.json produced by 01-setup-demo.sh
# 2) Verifies production is fast and staging is slow
# 3) Swaps staging -> production (bad code in prod)
# 4) Generates load to produce telemetry and trigger alerts
# 5) Optionally polls until recovery (after SRE Agent swaps back)

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
Usage: $0 [--request-count <n>] [--probe-path <path>] [--no-wait]

Options:
  --request-count <n>  Number of requests to generate (default: 80)
  --probe-path <path>  Path used for health/latency probes (default: /api/products)
  --dry-run            Only run pre-swap checks and exit
  --yes                Skip the interactive confirmation prompt before swapping
  --no-wait            Do not poll for recovery
EOF
}

request_count=80
wait_for_recovery=true
probe_path="${PROACTIVE_DEMO_PROBE_PATH:-/api/products}"
dry_run=false
auto_approve="${PROACTIVE_DEMO_AUTO_APPROVE:-false}"

healthy_ms_threshold="${PROACTIVE_DEMO_HEALTHY_MS:-1200}"
degraded_ms_threshold="${PROACTIVE_DEMO_DEGRADED_MS:-2000}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --request-count)
      request_count="${2:-}"; shift 2 ;;
    --probe-path)
      probe_path="${2:-}"; shift 2 ;;
    --dry-run)
      dry_run=true; shift ;;
    --yes)
      auto_approve=true; shift ;;
    --no-wait)
      wait_for_recovery=false; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "Unknown argument: $1" ;;
  esac
done

command -v az >/dev/null 2>&1 || die "Azure CLI (az) not found"
command -v python3 >/dev/null 2>&1 || die "python3 not found (used for JSON parsing)"
command -v curl >/dev/null 2>&1 || die "curl not found (used to generate load)"

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

# Prints one line to stdout:
#   OK <ms> <http_code>
#   HTTP_ERROR <ms> <http_code> <body_snippet>
#   CURL_ERROR <rc> <curl_error_snippet>
measure_http() {
  local url="$1"
  local max_time_s="${2:-60}"

  local resp_file err_file
  resp_file="$(mktemp)"
  err_file="$(mktemp)"

  local meta curl_rc http_code time_total ms
  meta="$(curl -sS --connect-timeout 10 --max-time "$max_time_s" -o "$resp_file" -w '%{http_code} %{time_total}' "$url" 2>"$err_file")"
  curl_rc=$?

  if (( curl_rc != 0 )); then
    local err
    err="$(tr '\n' ' ' <"$err_file" | head -c 240)"
    rm -f "$resp_file" "$err_file"
    printf 'CURL_ERROR %s %s\n' "$curl_rc" "$err"
    return 1
  fi

  http_code="${meta%% *}"
  time_total="${meta#* }"
  ms="$(to_ms "$time_total" 2>/dev/null || true)"
  [[ -n "$ms" ]] || ms=0

  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    rm -f "$resp_file" "$err_file"
    printf 'OK %s %s\n' "$ms" "$http_code"
    return 0
  fi

  local snippet
  snippet="$(head -c 240 "$resp_file" | tr '\n' ' ' | tr '\r' ' ')"
  rm -f "$resp_file" "$err_file"
  printf 'HTTP_ERROR %s %s %s\n' "$ms" "$http_code" "$snippet"
  return 2
}

# Returns response time (ms) to stdout for 2xx responses, otherwise fails.
measure_ms() {
  local url="$1"
  local max_time_s="${2:-60}"
  local line kind
  line="$(measure_http "$url" "$max_time_s")" || return 1
  kind="${line%% *}"
  if [[ "$kind" == "OK" ]]; then
    echo "${line#OK }" | awk '{print $1}'
    return 0
  fi
  return 1
}

probe_with_retries() {
  local url="$1"
  local attempts="${2:-5}"
  local delay_s="${3:-2}"

  local i last
  for ((i=1; i<=attempts; i++)); do
    last="$(measure_http "$url" 60)" && {
      echo "$last"
      return 0
    }
    sleep "$delay_s"
  done
  echo "$last"
  return 1
}

banner "PROACTIVE RELIABILITY DEMO (APP SERVICE SLOT SWAP)"
echo "  App Service:    $app_service_name"
echo "  Resource Group: $resource_group"
echo "  Production:     $prod_url"
echo "  Staging:        $staging_url"
echo

log_step "Checking current state"
log_info "Testing production (should be FAST)..."
if prod_ms="$(measure_ms "$prod_url$probe_path")"; then
  if [[ "$prod_ms" -lt "$healthy_ms_threshold" ]]; then log_ok "Production: ${prod_ms}ms - HEALTHY";
  else log_warn "Production: ${prod_ms}ms - SLOW (unexpected)"; fi
else
  log_warn "Production request failed: $(measure_http "$prod_url$probe_path" 60 | head -c 240 || true)"
fi

log_info "Testing staging (should be SLOW)..."
if staging_ms="$(measure_ms "$staging_url$probe_path")"; then
  if [[ "$staging_ms" -gt 1000 ]]; then log_ok "Staging: ${staging_ms}ms - SLOW (as expected)";
  else log_warn "Staging: ${staging_ms}ms - FAST (unexpected)"; fi
else
  log_warn "Staging request failed: $(measure_http "$staging_url$probe_path" 60 | head -c 240 || true)"
fi

if [[ "$dry_run" == "true" ]]; then
  log_ok "Dry run complete (no slot swap performed)."
  exit 0
fi

banner "READY TO SIMULATE BAD DEPLOYMENT"
echo "  Next step will SWAP staging (bad code) to production."
echo "  Ensure your SRE Agent is deployed (Privileged) + subagents/triggers configured."
echo
if [[ "$auto_approve" == "true" ]]; then
  log_info "Auto-approve enabled; performing the swap now."
else
  if ! read -r -p "  Press ENTER to perform the swap..." _; then
    log_warn "No interactive stdin detected; proceeding with swap."
  fi
fi

log_step "Swapping staging -> production"
swap_time="$(date +%H:%M:%S)"
az webapp deployment slot swap \
  --resource-group "$resource_group" \
  --name "$app_service_name" \
  --slot staging \
  --target-slot production \
  --output none 2>/dev/null
log_ok "Swap completed at $swap_time"

log_info "Waiting for swap to stabilize (15s)..."
sleep 15

banner "BAD CODE IS NOW IN PRODUCTION"
log_step "Verifying production is now slow"
if prod_ms2="$(measure_ms "$prod_url$probe_path")"; then
  if [[ "$prod_ms2" -gt "$degraded_ms_threshold" ]]; then log_warn "Production: ${prod_ms2}ms - DEGRADED";
  else log_warn "Production: ${prod_ms2}ms (may take a moment to show degradation)"; fi
else
  log_warn "Production request failed: $(measure_http "$prod_url$probe_path" 60 | head -c 240 || true)"
fi

log_step "Generating load ($request_count requests)"
endpoints=(
  "/api/products"
  "/api/products/1"
  "/api/products/2"
  "/api/products/search?query=electronics"
)

sum=0
count=0
slow_count=0
critical_count=0
max_ms=0

for ((i=1; i<=request_count; i++)); do
  endpoint="${endpoints[RANDOM % ${#endpoints[@]}]}"
  url="$prod_url$endpoint"

  if ms="$(measure_ms "$url" 60)"; then
    sum=$((sum + ms))
    count=$((count + 1))
    if (( ms > max_ms )); then max_ms=$ms; fi

    if (( ms > 2000 )); then
      printf '  [%d/%d] %dms CRITICAL\n' "$i" "$request_count" "$ms"
      critical_count=$((critical_count + 1))
    elif (( ms > 1000 )); then
      printf '  [%d/%d] %dms SLOW\n' "$i" "$request_count" "$ms"
      slow_count=$((slow_count + 1))
    else
      printf '  [%d/%d] %dms\n' "$i" "$request_count" "$ms"
    fi
  else
    diag="$(measure_http "$url" 60 | head -c 260 || true)"
    printf '  [%d/%d] FAILED %s\n' "$i" "$request_count" "$diag"
  fi

  sleep 0.2
 done

echo
if (( count > 0 )); then
  avg=$((sum / count))
  echo "  Load Summary:"
  echo "    Requests: $request_count"
  echo "    Average:  ${avg}ms"
  echo "    Max:      ${max_ms}ms"
  echo "    Slow:     ${slow_count}"
  echo "    Critical: ${critical_count}"
fi

banner "WAITING FOR SRE AGENT"
echo "  Azure Monitor alerts typically fire within a few minutes."
echo "  SRE Agent remediation command (rollback) is a slot swap back."
echo

if [[ "$wait_for_recovery" == "true" ]]; then
  echo "  Polling production every 30 seconds (up to ~12 minutes)..."
  attempts=0
  max_attempts=24
  recovered=false

  while [[ "$recovered" != "true" && $attempts -lt $max_attempts ]]; do
    attempts=$((attempts + 1))

    if ms="$(measure_ms "$prod_url$probe_path")"; then
      if (( ms < healthy_ms_threshold )); then
        recovered=true
        log_ok "Recovered: ${ms}ms"
        break
      fi
      log_info "Not yet recovered: ${ms}ms (attempt ${attempts}/${max_attempts})"
    else
      log_warn "Request failed (attempt ${attempts}/${max_attempts}): $(measure_http "$prod_url$probe_path" 60 | head -c 240 || true)"
    fi

    sleep 30
  done

  if [[ "$recovered" != "true" ]]; then
    log_warn "Timed out waiting for recovery. Check SRE Agent execution history + alert firing."
  fi
fi

log_ok "Demo run complete."