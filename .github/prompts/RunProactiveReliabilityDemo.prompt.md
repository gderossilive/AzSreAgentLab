# RunProactiveReliabilityDemo

## Description
Run the **Proactive Reliability (App Service slot swap)** demo in this repo.

What it does:
- Deploys an App Service + `staging` slot + App Insights + an Activity Log Alert for slot swap.
- Publishes a **GOOD (fast)** build to `production` and a **BAD (slow)** build to `staging`.
- Performs a slot swap to push the bad build into production, generates load, and waits for Azure SRE Agent to detect regression and remediate by swapping back.

This prompt summarizes the exact workflow and values used in the session on 2026-01-23.

## Inputs (fill at runtime)
Avoid pasting environment-specific identifiers into this prompt (subscription IDs, app names, URLs, etc.).

At runtime, collect values from:
- Azure CLI current account (`az account show`)
- The demo output file: `demos/ProactiveReliabilityAppService/demo-config.json`

Quick way to print the current demo values (no secrets, but keep them out of reusable docs):

```bash
cd /workspaces/AzSreAgentLab/demos/ProactiveReliabilityAppService
python3 - <<'PY'
import json
j=json.load(open('demo-config.json'))
for k in ['SubscriptionId','Location','ResourceGroupName','AppServiceName','ProductionUrl','StagingUrl','ApplicationInsightsName']:
  print(f"{k}={j.get(k)}")
PY
```

## Useful discovery commands (sanitized workflow)
These commands help you retrieve the values you need *at runtime* without hardcoding them in docs.

### 1) Confirm current subscription/tenant (sanitized)
```bash
az account show --query '{subscriptionId:id, subscriptionName:name, tenantId:tenantId, user:user.name}' -o json
```

### 2) Load demo-config.json into shell variables
```bash
cd /workspaces/AzSreAgentLab/demos/ProactiveReliabilityAppService

export DEMO_RG="$(python3 -c "import json;print(json.load(open('demo-config.json'))['ResourceGroupName'])")"
export DEMO_APP="$(python3 -c "import json;print(json.load(open('demo-config.json'))['AppServiceName'])")"
export DEMO_AI="$(python3 -c "import json;print(json.load(open('demo-config.json'))['ApplicationInsightsName'])")"

echo "DEMO_RG=$DEMO_RG"
echo "DEMO_APP=$DEMO_APP"
echo "DEMO_AI=$DEMO_AI"
```

### 3) Resource IDs (safe to display)
App Service resource ID:
```bash
az resource show -g "$DEMO_RG" -n "$DEMO_APP" --resource-type Microsoft.Web/sites --query id -o tsv
```

App Insights resource ID:
```bash
az resource show -g "$DEMO_RG" -n "$DEMO_AI" --resource-type microsoft.insights/components --query id -o tsv
```

### 4) App Insights AppId (needed by the SRE Agent tools)
```bash
az resource show -g "$DEMO_RG" -n "$DEMO_AI" --resource-type microsoft.insights/components --query properties.AppId -o tsv
```

### 5) Find SRE Agent in the demo RG (safe to display)
List agent resources:
```bash
az resource list -g "$DEMO_RG" --resource-type Microsoft.App/agents --query "[].name" -o tsv
```

Show agent endpoint + action mode:
```bash
export SRE_AGENT_NAME="$(az resource list -g "$DEMO_RG" --resource-type Microsoft.App/agents --query "[0].name" -o tsv)"
az resource show -g "$DEMO_RG" -n "$SRE_AGENT_NAME" --resource-type Microsoft.App/agents \
  --query '{name:name, endpoint:properties.agentEndpoint, actionMode:properties.actionConfiguration.mode, accessLevel:properties.actionConfiguration.accessLevel, runningState:properties.runningState}' -o json
```

### 6) (Sensitive) App Insights connection string
Only needed if you must update the SRE Agent log configuration. Treat the output as sensitive and do not paste it into prompts/docs.
```bash
az resource show -g "$DEMO_RG" -n "$DEMO_AI" --resource-type microsoft.insights/components --query properties.ConnectionString -o tsv
```

## Checklist

### 0) Prereqs
- Azure CLI logged in: `az login`
- Correct subscription selected:
  - `az account set --subscription <SUBSCRIPTION_ID>`
- You have permission to deploy to the demo RG (Contributor is fine).

### 1) (Re)deploy infra + publish GOOD/BAD app versions
From repo root:

```bash
cd /workspaces/AzSreAgentLab/demos/ProactiveReliabilityAppService
./scripts/01-setup-demo.sh \
  --resource-group <DEMO_RESOURCE_GROUP> \
  --app-service-name <APP_SERVICE_NAME> \
  --location <AZURE_REGION> \
  --subscription-id <SUBSCRIPTION_ID>
```

Expected:
- Updates/creates `demo-config.json`.
- `production` responds fast and `staging` responds slow.

### 2) Ensure SRE Agent exists in the SAME demo RG and can remediate
Verify the agent exists:

```bash
az resource list -g <DEMO_RESOURCE_GROUP> --resource-type Microsoft.App/agents -o table
```

Ensure action mode is `Autonomous`:

```bash
az resource update \
  -g <DEMO_RESOURCE_GROUP> \
  -n <SRE_AGENT_NAME> \
  --resource-type Microsoft.App/agents \
  --set properties.actionConfiguration.mode=Autonomous
```

Note:
- If you see a validation error about App Insights (`AppId and ConnectionString fields must be provided together`), update the agent’s `properties.logConfiguration.applicationInsightsConfiguration` with both values (AppId + ConnectionString) at the same time.

### 3) Configure subagents + triggers in the SRE Agent portal
Templates live here:
- `demos/ProactiveReliabilityAppService/SubAgents/AvgResponseBaseline.yaml`
- `demos/ProactiveReliabilityAppService/SubAgents/DeploymentHealthCheck.yaml`
- `demos/ProactiveReliabilityAppService/SubAgents/DeploymentReporter.yaml`

Replace placeholders in the YAML templates using values from `demo-config.json`.

You still may need to edit `DeploymentReporter.yaml` to remove or replace:
- `<YOUR_TEAMS_CHANNEL_URL>`
- `<YOUR_EMAIL_ADDRESS>`

Recommended triggers (portal):
- Scheduled trigger (every 15m) → `AvgResponseTime` (writes `baseline.txt`)
- Incident trigger (slot swap activity log alert) → `DeploymentHealthCheck`
- Optional scheduled trigger (daily) → `DeploymentReporter`

### 4) Run the live demo (swap + load + wait)

```bash
cd /workspaces/AzSreAgentLab/demos/ProactiveReliabilityAppService
./scripts/02-run-demo.sh
```

Notes:
- The script will pause for ENTER before swapping; to run non-interactively, use `--yes`:

```bash
./scripts/02-run-demo.sh --yes
```

- If you're using VS Code tasks, you can run the `run-proactive-reliability-demo` task.

- The default probe path is `/api/products`.

### 5) If recovery times out
In this session, the runner timed out waiting for recovery.

Do these checks:
- In the SRE Agent portal, confirm the incident trigger fired and `DeploymentHealthCheck` ran.
- Confirm `AvgResponseTime` baseline ran recently and `baseline.txt` exists in the agent knowledge store.
- Confirm the slot swap Activity Log Alert exists and is scoped to `rg-sre-proactive-demo`.
- Confirm the agent action mode is `Autonomous`.

### 6) Reset back to baseline (GOOD in prod, BAD in staging)

```bash
cd /workspaces/AzSreAgentLab/demos/ProactiveReliabilityAppService
./scripts/03-reset-demo.sh
```

If probing is inconclusive and you still want to force it:

```bash
./scripts/03-reset-demo.sh --force-swap
```

## Cleanup
Delete the demo RG:

```bash
az group delete -n <DEMO_RESOURCE_GROUP> --yes --no-wait
```
