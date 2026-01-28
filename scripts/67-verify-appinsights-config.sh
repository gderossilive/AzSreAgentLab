#!/usr/bin/env bash
set -euo pipefail

# Verify Octopets backend telemetry config (App Insights + sampling).
# This is a config sanity check (no secrets printed).
#
# Usage:
#   source scripts/load-env.sh
#   scripts/67-verify-appinsights-config.sh

: "${OCTOPETS_RG_NAME:?Missing OCTOPETS_RG_NAME}"
: "${OCTOPETS_API_APP_NAME:=octopetsapi}"

api_app="$OCTOPETS_API_APP_NAME"

echo "Checking Application Insights resource in $OCTOPETS_RG_NAME..."
app_insights_name="$(az resource list -g "$OCTOPETS_RG_NAME" --resource-type microsoft.insights/components --query "[?tags.\"aspire-resource-name\"=='octopets-appinsights'][0].name" -o tsv)"
if [[ -z "$app_insights_name" ]]; then
  # Fallback: some deployments don't carry Aspire tags.
  app_insights_name="$(az resource list -g "$OCTOPETS_RG_NAME" --resource-type microsoft.insights/components --query "[0].name" -o tsv)"
fi
app_insights_cs=""
if [[ -n "$app_insights_name" ]]; then
  app_insights_cs="$(az resource show -g "$OCTOPETS_RG_NAME" -n "$app_insights_name" --resource-type microsoft.insights/components --query properties.ConnectionString -o tsv 2>/dev/null || true)"
fi

if [[ -z "$app_insights_name" ]]; then
  echo "FAIL: App Insights component not found (tag aspire-resource-name=octopets-appinsights)." >&2
  exit 1
fi

if [[ -z "$app_insights_cs" ]]; then
  echo "FAIL: App Insights exists ($app_insights_name) but connectionString was not returned." >&2
  exit 1
fi

echo "OK: App Insights component found: $app_insights_name"

echo "Checking Container App env var wiring on $api_app..."
# Check env vars without exposing secret values
ai_secret_ref="$(az containerapp show -g "$OCTOPETS_RG_NAME" -n "$api_app" --query "properties.template.containers[0].env[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING'].secretRef | [0]" -o tsv || true)"
sampler_env="$(az containerapp show -g "$OCTOPETS_RG_NAME" -n "$api_app" --query "properties.template.containers[0].env[?name=='OTEL_TRACES_SAMPLER'].value" -o tsv || true)"

if [[ -z "$ai_secret_ref" ]]; then
  echo "FAIL: APPLICATIONINSIGHTS_CONNECTION_STRING is not configured with secretRef on $api_app." >&2
  echo "      Expected secretRef=appinsights-connection-string." >&2
  echo "      Run scripts/31-deploy-octopets-containers.sh to apply configuration." >&2
  exit 1
fi

if [[ "$ai_secret_ref" != "appinsights-connection-string" ]]; then
  echo "FAIL: APPLICATIONINSIGHTS_CONNECTION_STRING secretRef is '$ai_secret_ref' (expected: appinsights-connection-string)." >&2
  echo "      Run scripts/31-deploy-octopets-containers.sh to apply configuration." >&2
  exit 1
fi

if [[ "$sampler_env" != "always_on" ]]; then
  echo "FAIL: OTEL_TRACES_SAMPLER is not set to always_on on $api_app (current: '${sampler_env:-<unset>}')." >&2
  exit 1
fi

echo "OK: Env vars present (APPLICATIONINSIGHTS_CONNECTION_STRING=secretref:..., OTEL_TRACES_SAMPLER=always_on)"

echo "Checking Container App secret exists..."
secret_names="$(az containerapp secret list -g "$OCTOPETS_RG_NAME" -n "$api_app" --query "[].name" -o tsv)"
if ! grep -qx "appinsights-connection-string" <<<"$secret_names"; then
  echo "FAIL: Secret 'appinsights-connection-string' not found on $api_app." >&2
  exit 1
fi

echo "OK: Secret 'appinsights-connection-string' present"

echo "Done. Telemetry should flow when the app receives traffic (exceptions are recorded via Activity.AddException + ILogger scopes)."
