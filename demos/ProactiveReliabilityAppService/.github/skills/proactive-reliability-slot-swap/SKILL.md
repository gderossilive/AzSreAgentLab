---
name: proactive-reliability-slot-swap
description: >
  Run the Proactive Reliability App Service slot swap demo. Verifies the App Service baseline,
  checks the Azure SRE Agent is ready, swaps staging to production, generates load, and waits
  for autonomous remediation. USE FOR: run proactive reliability demo, run slot swap demo,
  web app slot swap demo, App Service regression demo, Demo1, RunProactiveReliabilityDemo.
  DO NOT USE FOR: deploying the demo from scratch (use 01-setup-demo.sh), resetting the demo
  after the run (use 03-reset-demo.sh), or generic App Service troubleshooting.
---

# Proactive Reliability Slot Swap - Demo Skill

Run the Proactive Reliability App Service demo that intentionally swaps the slow staging build
into production, generates telemetry, and waits for Azure SRE Agent to remediate by swapping back.

## Working directory

Always run commands from the Proactive Reliability demo directory:

```bash
cd /workspaces/AzSreAgentLab/demos/ProactiveReliabilityAppService
```

## Step 1: Show current demo values

Use `demo-config.json` as the source of truth. Print the current values without exposing secrets:

```bash
python3 - <<'PY'
import json
j=json.load(open('demo-config.json'))
for k in ['SubscriptionId','Location','ResourceGroupName','AppServiceName','ProductionUrl','StagingUrl','ApplicationInsightsName']:
  print(f"{k}={j.get(k)}")
PY
```

## Step 2: Verify prerequisites

### 2a) App Service baseline is correct

Production should be faster than staging on the probe path.

```bash
PROD=$(python3 -c "import json;print(json.load(open('demo-config.json'))['ProductionUrl'].rstrip('/'))")
STAGING=$(python3 -c "import json;print(json.load(open('demo-config.json'))['StagingUrl'].rstrip('/'))")

curl -sS -o /dev/null -w "prod code=%{http_code} time=%{time_total}s\n" "$PROD/api/products"
curl -sS -o /dev/null -w "staging code=%{http_code} time=%{time_total}s\n" "$STAGING/api/products"
```

Expected state: production is healthy and materially faster than staging.

### 2b) Azure CLI context matches the demo

```bash
az account show --query '{subscriptionId:id, subscriptionName:name, tenantId:tenantId, user:user.name}' -o json
```

The selected subscription should match `SubscriptionId` from `demo-config.json`.

### 2c) Azure SRE Agent is ready to act

The agent must be deployed in the same resource group, in autonomous mode, with privileged access.

```bash
DEMO_RG="$(python3 -c "import json;print(json.load(open('demo-config.json'))['ResourceGroupName'])")"

az resource list -g "$DEMO_RG" --resource-type Microsoft.App/agents --query "[].name" -o tsv

SRE_AGENT_NAME="$(az resource list -g "$DEMO_RG" --resource-type Microsoft.App/agents --query "[0].name" -o tsv)"
az resource show -g "$DEMO_RG" -n "$SRE_AGENT_NAME" --resource-type Microsoft.App/agents \
  --query '{name:name, endpoint:properties.agentEndpoint, actionMode:properties.actionConfiguration.mode, accessLevel:properties.actionConfiguration.accessLevel, runningState:properties.runningState}' -o json
```

If the action mode is not `Autonomous`, switch it:

```bash
az resource update -g "$DEMO_RG" -n "$SRE_AGENT_NAME" --resource-type Microsoft.App/agents \
  --set properties.actionConfiguration.mode=Autonomous
```

Agent-side prerequisites that must already be configured in the portal:

- Subagent templates from `SubAgents/`
- A scheduled baseline task that writes a fresh baseline artifact
- An incident trigger tied to the slot swap activity log alert

## Step 3: Run the demo

Recommended non-interactive run:

```bash
./scripts/02-run-demo.sh --yes
```

Interactive run:

```bash
./scripts/02-run-demo.sh
```

Useful options:

```bash
./scripts/02-run-demo.sh --dry-run
./scripts/02-run-demo.sh --no-wait
./scripts/02-run-demo.sh --request-count 120
./scripts/02-run-demo.sh --probe-path /api/products
```

## Expected outcome

- The script confirms production is faster than staging before the swap
- `staging` is swapped into `production`
- Load is generated so telemetry and the slot swap alert can fire
- Azure SRE Agent detects the regression and runs the deployment health workflow
- Production returns to healthy latency after remediation

## Troubleshooting

If the script times out waiting for recovery, verify the slot swap activity and agent state.

### Check recent slot swap activity

```bash
SUB=$(az account show --query id -o tsv)
START=$(date -u -d '90 minutes ago' +%Y-%m-%dT%H:%M:%SZ)
DEMO_RG="$(python3 -c "import json;print(json.load(open('demo-config.json'))['ResourceGroupName'])")"

FILTER=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=\"()'=$ ,\"))" \
  "eventTimestamp ge '$START' and resourceGroupName eq '$DEMO_RG'")

az rest --method get --url \
  "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Insights/eventtypes/management/values?api-version=2015-04-01&\$filter=$FILTER" \
  --query "value[?contains(operationName.value, 'slotsswap')].{time:eventTimestamp,status:status.value,op:operationName.value,caller:caller}" -o table
```

### Check agent readiness again

- Confirm the incident trigger fired in the SRE Agent portal
- Confirm the baseline artifact exists and is fresh
- If `runningState` remains `BuildingKnowledgeGraph`, remediation may be delayed
- Confirm production is actually slower than the stored baseline by a meaningful margin

## Constraints

- Do not use this skill to deploy the demo from scratch
- Do not hardcode resource identifiers; use `demo-config.json` and the active Azure CLI context
- Do not reset the environment during the run unless the user explicitly asks for recovery/reset
