#!/usr/bin/env bash
set -euo pipefail

# Deploy Octopets application containers using ACR remote builds.
# Run this after 30-deploy-octopets.sh provisions the infrastructure.
#
# Usage:
#   source scripts/load-env.sh
#   scripts/31-deploy-octopets-containers.sh

: "${OCTOPETS_RG_NAME:?Missing OCTOPETS_RG_NAME}"

# Discover ACR and Container Apps Environment
acr_name="$(az acr list -g "$OCTOPETS_RG_NAME" --query "[0].name" -o tsv)"
cae_name="$(az containerapp env list -g "$OCTOPETS_RG_NAME" --query "[0].name" -o tsv)"

if [[ -z "$acr_name" ]]; then
  echo "ERROR: Could not find AZURE_CONTAINER_REGISTRY_NAME in azd environment" >&2
  exit 1
fi

if [[ -z "$cae_name" ]]; then
  echo "ERROR: Could not find Container Apps Environment in $OCTOPETS_RG_NAME" >&2
  exit 1
fi

login_server="$(az acr show -n "$acr_name" --query loginServer -o tsv)"
stamp="$(date -u +%Y%m%d%H%M%S)"
api_tag="${login_server}/octopetsapi:${stamp}"
fe_tag="${login_server}/octopetsfe:${stamp}"

# Build backend image in ACR
echo "Building backend image in ACR: $api_tag"
backend_dockerfile="/workspaces/AzSreAgentLab/external/octopets/backend/Dockerfile"
if [[ ! -f "$backend_dockerfile" ]]; then
  cat > "$backend_dockerfile" <<'EOF'
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY ../servicedefaults ./servicedefaults
COPY . .
RUN dotnet restore ./Octopets.Backend.csproj
RUN dotnet publish ./Octopets.Backend.csproj -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:9.0
WORKDIR /app
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet","Octopets.Backend.dll"]
EOF
fi

cd /workspaces/AzSreAgentLab/external/octopets
az acr build -r "$acr_name" -t "$api_tag" -f backend/Dockerfile .

# Build frontend image in ACR
echo "Building frontend image in ACR: $fe_tag"
az acr build -r "$acr_name" -t "$fe_tag" \
  --build-arg REACT_APP_USE_MOCK_DATA=false \
  -f frontend/Dockerfile \
  .
cd /workspaces/AzSreAgentLab

# Deploy containers to Container Apps
api_app="octopetsapi"
fe_app="octopetsfe"

echo "Updating backend container app: $api_app"
az containerapp update -g "$OCTOPETS_RG_NAME" -n "$api_app" \
  --container-name "$api_app" \
  --image "$api_tag" \
  --query "properties.configuration.ingress.fqdn" -o tsv >/dev/null || \
az containerapp create -g "$OCTOPETS_RG_NAME" -n "$api_app" \
  --environment "$cae_name" \
  --image "$api_tag" \
  --registry-server "$login_server" \
  --registry-identity system \
  --ingress external \
  --target-port 8080 \
  --env-vars "EnableSwagger=true" "ASPNETCORE_URLS=http://+:8080" \
  --query "properties.configuration.ingress.fqdn" -o tsv >/dev/null

# Configure Application Insights + OpenTelemetry
# Note: The backend uses the Aspire ServiceDefaults Azure Monitor exporter.
# It activates when APPLICATIONINSIGHTS_CONNECTION_STRING is present.
app_insights_name="$(az resource list -g "$OCTOPETS_RG_NAME" --resource-type microsoft.insights/components --query "[?tags.\"aspire-resource-name\"=='octopets-appinsights'][0].name" -o tsv)"
if [[ -z "$app_insights_name" ]]; then
  # Fallback: some deployments don't carry Aspire tags.
  app_insights_name="$(az resource list -g "$OCTOPETS_RG_NAME" --resource-type microsoft.insights/components --query "[0].name" -o tsv)"
fi
app_insights_cs=""
if [[ -n "$app_insights_name" ]]; then
  app_insights_cs="$(az resource show -g "$OCTOPETS_RG_NAME" -n "$app_insights_name" --resource-type microsoft.insights/components --query properties.ConnectionString -o tsv 2>/dev/null || true)"
fi

if [[ -z "$app_insights_cs" ]]; then
  echo "WARN: App Insights connection string not found in $OCTOPETS_RG_NAME." >&2
  echo "      Telemetry will not be exported to Application Insights until it's configured." >&2
else
  echo "Configuring Application Insights on $api_app"${app_insights_name:+" ("$app_insights_name")"}

  # Store the connection string as a Container Apps secret (do not print it)
  az containerapp secret set -g "$OCTOPETS_RG_NAME" -n "$api_app" \
    --secrets "appinsights-connection-string=$app_insights_cs" >/dev/null

  # Ensure traces are sampled 100% so errors/traces aren't dropped by the SDK
  az containerapp update -g "$OCTOPETS_RG_NAME" -n "$api_app" \
    --container-name "$api_app" \
    --set-env-vars \
      "APPLICATIONINSIGHTS_CONNECTION_STRING=secretref:appinsights-connection-string" \
      "OTEL_TRACES_SAMPLER=always_on" \
    >/dev/null
fi

api_fqdn="$(az containerapp show -g "$OCTOPETS_RG_NAME" -n "$api_app" --query "properties.configuration.ingress.fqdn" -o tsv)"
api_url="https://${api_fqdn}"

echo "Updating frontend container app: $fe_app"
az containerapp update -g "$OCTOPETS_RG_NAME" -n "$fe_app" \
  --container-name "$fe_app" \
  --image "$fe_tag" \
  --set-env-vars "services__octopetsapi__https__0=${api_url}" \
  --query "properties.configuration.ingress.fqdn" -o tsv >/dev/null || \
az containerapp create -g "$OCTOPETS_RG_NAME" -n "$fe_app" \
  --environment "$cae_name" \
  --image "$fe_tag" \
  --registry-server "$login_server" \
  --registry-identity system \
  --ingress external \
  --target-port 80 \
  --env-vars "services__octopetsapi__https__0=${api_url}" \
  --query "properties.configuration.ingress.fqdn" -o tsv >/dev/null

fe_fqdn="$(az containerapp show -g "$OCTOPETS_RG_NAME" -n "$fe_app" --query "properties.configuration.ingress.fqdn" -o tsv)"
fe_url="https://${fe_fqdn}"

"${PWD}/scripts/set-dotenv-value.sh" "OCTOPETS_API_URL" "$api_url"
"${PWD}/scripts/set-dotenv-value.sh" "OCTOPETS_FE_URL" "$fe_url"

echo "Octopets containers deployed successfully!"
echo "Frontend: $fe_url"
echo "Backend: $api_url"
