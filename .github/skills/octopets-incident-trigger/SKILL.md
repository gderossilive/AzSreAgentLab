---
name: octopets-incident-trigger
description: >
  Trigger a real, temporary anomaly on the Octopets Azure Container Apps by enabling backend
  CPU stress and memory errors, generating frontend and API traffic, verifying the impact, and
  cleaning up completely. USE FOR: trigger Octopets anomaly, run Demo3 ServiceNow Octopets,
  induce Octopets incident, create Container Apps anomaly for ServiceNow demo, Octopets CPU
  stress and memory errors, validate health-check or incident pipeline on Octopets. DO NOT USE
  FOR: initial Octopets deployment, generic Azure Container Apps troubleshooting, ServiceNow
  connector setup, or permanent stress/load testing.
---

# Octopets Incident Trigger - Demo Skill

Run the Octopets incident scenario that temporarily degrades the backend Container App and drives
traffic through both the frontend and API so the anomaly is visible in client behavior and Azure
metrics.

## Working directory

Always run commands from the repository root:

```bash
cd /workspaces/AzSreAgentLab
```

## Step 1: Fast prerequisite check

Load the deployed Octopets environment variables without printing secrets:

```bash
source scripts/load-env.sh
```

Ensure Azure CLI is authenticated and using the intended subscription:

```bash
./scripts/20-az-login.sh
az account show --query '{subscriptionId:id, subscriptionName:name, tenantId:tenantId, user:user.name}' -o json
```

Confirm the required non-secret environment variables are present:

```bash
echo "$OCTOPETS_RG_NAME"
echo "$OCTOPETS_FE_URL"
echo "$OCTOPETS_API_URL"
```

Confirm both Octopets Container Apps exist and are running:

```bash
az containerapp list -g "$OCTOPETS_RG_NAME" -o table
az containerapp show -g "$OCTOPETS_RG_NAME" -n octopetsfe  --query '{name:name,status:properties.runningStatus}' -o table
az containerapp show -g "$OCTOPETS_RG_NAME" -n octopetsapi --query '{name:name,status:properties.runningStatus}' -o table
```

Do not continue if either app is missing or not in a running state.

## Step 2: Trigger the anomaly

Enable both backend injectors:

```bash
./scripts/61-enable-cpu-stress.sh
./scripts/63-enable-memory-errors.sh
```

Then generate traffic for 15 minutes. This script drives requests to both the frontend and API,
so the frontend participates in the scenario while the backend carries the actual stressors.

```bash
./scripts/60-generate-traffic.sh 15
```

If the first run is not enough to surface the behavior, increase pressure carefully by running
two or three traffic generators in parallel. This increases cost and resource pressure.

```bash
./scripts/60-generate-traffic.sh 15 &
./scripts/60-generate-traffic.sh 15 &
wait
```

## Step 3: Verify the anomaly quickly

Confirm the backend injectors are set on `octopetsapi`:

```bash
az containerapp show -g "$OCTOPETS_RG_NAME" -n octopetsapi \
  --query "properties.template.containers[0].env[?name=='CPU_STRESS' || name=='MEMORY_ERRORS']" -o table
```

Capture the frontend and backend resource IDs for portal navigation or downstream tooling:

```bash
FE_ID=$(az containerapp show -g "$OCTOPETS_RG_NAME" -n octopetsfe  --query id -o tsv)
API_ID=$(az containerapp show -g "$OCTOPETS_RG_NAME" -n octopetsapi --query id -o tsv)
echo "FE_ID=$FE_ID"
echo "API_ID=$API_ID"
```

Observe symptoms during traffic generation:

- `./scripts/60-generate-traffic.sh` reports per-interval frontend and API success/failure marks
- Azure Portal Container App metrics should show elevated CPU, memory, request volume, latency,
  and possibly `5xx` on the backend
- If the incident is being used to validate a scheduled health-check or ServiceNow path, wait
  about 5 to 15 minutes for metric rollups before manually running the downstream agent workflow

Optional direct metric check via ARM:

```bash
az rest --method get --uri "https://management.azure.com/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$OCTOPETS_RG_NAME/providers/Microsoft.App/containerApps/octopetsapi/providers/microsoft.insights/metrics?api-version=2018-01-01&metricnames=WorkingSetBytes,Requests,ResponseTime&interval=PT1M"
```

## Step 4: Clean up completely

Disable both backend injectors:

```bash
./scripts/62-disable-cpu-stress.sh
./scripts/64-disable-memory-errors.sh
```

If you started traffic generators in the background, let them exit at the configured duration or
stop them explicitly with `Ctrl+C` from their terminal sessions.

After cleanup, verify the flags are disabled:

```bash
az containerapp show -g "$OCTOPETS_RG_NAME" -n octopetsapi \
  --query "properties.template.containers[0].env[?name=='CPU_STRESS' || name=='MEMORY_ERRORS']" -o table
```

## Constraints

- Do not request or print secrets, tokens, passwords, webhook URLs, or connection strings
- Prefer the built-in repo scripts instead of ad hoc Container App mutations
- Do not require Docker or local image builds
- Keep the test short, reversible, and followed by cleanup
- Treat parallel traffic generation as an escalation step, not the default

## Success criteria

- Both Container Apps are confirmed running before the test starts
- The backend anomaly is enabled and traffic is generated through both frontend and API
- The impact is observable through script output and/or Azure metrics
- Cleanup returns the backend injector flags to a disabled state