# RunProactiveReliabilityDemo

## Goal
Run the **Proactive Reliability (App Service slot swap)** demo runner script:

- Swap `staging` → `production` so the “BAD/slow” build becomes production.
- Generate load so telemetry + the slot-swap alert can fire.
- Wait for Azure SRE Agent to detect the regression and remediate (swap back).

This prompt intentionally does **not** cover deployment or reset scripts. It focuses only on running the runner script with its prerequisites already satisfied.

## Inputs (fill at runtime)
Avoid hardcoding environment-specific identifiers into this prompt.

At runtime, source values from:

- Azure CLI current account: `az account show`
- Demo config file: `demos/ProactiveReliabilityAppService/demo-config.json`

Print the current demo values (safe, no secrets):

```bash
cd /workspaces/AzSreAgentLab/demos/ProactiveReliabilityAppService
python3 - <<'PY'
import json
j=json.load(open('demo-config.json'))
for k in ['SubscriptionId','Location','ResourceGroupName','AppServiceName','ProductionUrl','StagingUrl','ApplicationInsightsName']:
  print(f"{k}={j.get(k)}")
PY
```

## Prerequisites (must be true before running)

### 1) App + slots already exist and match the expected “baseline”

- `demo-config.json` exists and points to a working App Service + `staging` slot.
- Production responds **faster** than staging on the probe path (default `/api/products`).

Quick sanity check (should show production faster than staging):

```bash
cd /workspaces/AzSreAgentLab/demos/ProactiveReliabilityAppService

PROD=$(python3 -c "import json;print(json.load(open('demo-config.json'))['ProductionUrl'].rstrip('/'))")
STAGING=$(python3 -c "import json;print(json.load(open('demo-config.json'))['StagingUrl'].rstrip('/'))")

curl -sS -o /dev/null -w "prod code=%{http_code} time=%{time_total}s\n" "$PROD/api/products"
curl -sS -o /dev/null -w "staging code=%{http_code} time=%{time_total}s\n" "$STAGING/api/products"
```

### 2) Azure CLI access

- Logged in: `az login`
- Correct subscription selected (match demo-config.json):

```bash
az account show --query '{subscriptionId:id, subscriptionName:name, tenantId:tenantId, user:user.name}' -o json
```

### 3) Azure SRE Agent is ready to act on this app

You need an SRE Agent deployed in the **same resource group** as the App Service referenced by `demo-config.json`.

Minimum requirements:

- Agent access level is **Privileged** (able to perform slot swap remediation).
- Action mode is **Autonomous**.
- The agent has the required subagents + triggers configured in the portal.
- A baseline exists and is fresh (for example, `baseline.txt` created by a scheduled baseline subagent).

Discover the agent and show basic status (safe):

```bash
cd /workspaces/AzSreAgentLab/demos/ProactiveReliabilityAppService

DEMO_RG="$(python3 -c "import json;print(json.load(open('demo-config.json'))['ResourceGroupName'])")"

az resource list -g "$DEMO_RG" --resource-type Microsoft.App/agents --query "[].name" -o tsv

SRE_AGENT_NAME="$(az resource list -g "$DEMO_RG" --resource-type Microsoft.App/agents --query "[0].name" -o tsv)"
az resource show -g "$DEMO_RG" -n "$SRE_AGENT_NAME" --resource-type Microsoft.App/agents \
  --query '{name:name, endpoint:properties.agentEndpoint, actionMode:properties.actionConfiguration.mode, accessLevel:properties.actionConfiguration.accessLevel, runningState:properties.runningState}' -o json
```

If action mode is not Autonomous:

```bash
az resource update -g "$DEMO_RG" -n "$SRE_AGENT_NAME" --resource-type Microsoft.App/agents \
  --set properties.actionConfiguration.mode=Autonomous
```

Notes on portal setup (you do this in the SRE Agent portal):

- Subagent templates are in `demos/ProactiveReliabilityAppService/SubAgents/`.
- Recommended triggers:
  - Scheduled (every 15m): baseline task → writes `baseline.txt`
  - Incident trigger: slot swap Activity Log Alert → deployment health check

## Run the demo

Run interactively (will prompt before swapping):

```bash
cd /workspaces/AzSreAgentLab/demos/ProactiveReliabilityAppService
./scripts/02-run-demo.sh
```

Run non-interactively (recommended for demos):

```bash
cd /workspaces/AzSreAgentLab/demos/ProactiveReliabilityAppService
./scripts/02-run-demo.sh --yes
```

Useful options:

- `--dry-run`: validate current prod/staging behavior without swapping.
- `--no-wait`: perform swap + load but do not poll for recovery.
- `--request-count <n>`: increase/decrease traffic.
- `--probe-path <path>`: if your API path differs.

## What “success” looks like

- Script confirms production is **fast** and staging is **slow**.
- Script swaps staging → production, then production becomes **slow**.
- Within a few minutes, the slot swap **alert** and the **incident trigger** fire.
- SRE Agent runs the health-check workflow and remediates by swapping back.
- Script observes production return to “healthy” latency before timeout.

## Troubleshooting (if recovery times out)

1) Verify the swap activity happened (safe, avoids `az monitor` if your CLI module is unavailable):

```bash
SUB=$(az account show --query id -o tsv)
START=$(date -u -d '90 minutes ago' +%Y-%m-%dT%H:%M:%SZ)

FILTER=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=\"()'=$ ,\"))" \
  "eventTimestamp ge '$START' and resourceGroupName eq '$DEMO_RG'")

az rest --method get --url \
  "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Insights/eventtypes/management/values?api-version=2015-04-01&\$filter=$FILTER" \
  --query "value[?contains(operationName.value, 'slotsswap')].{time:eventTimestamp,status:status.value,op:operationName.value,caller:caller}" -o table
```

2) In the SRE Agent portal:

- Confirm the incident trigger fired from the slot swap alert.
- Confirm the health-check subagent ran.
- Confirm the baseline artifact exists and is recent.

3) Confirm agent readiness:

- If `runningState` stays `BuildingKnowledgeGraph`, remediation may be delayed.
- Confirm access level is Privileged and action mode is Autonomous.

4) Confirm production is actually degraded:

- If production isn’t consistently slower than your baseline/threshold, the agent may not decide to remediate.

