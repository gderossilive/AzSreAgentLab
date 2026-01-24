```prompt
---
agent: agent
---
You are helping a contributor **run (trigger) the Azure Health Check demo** after it has been set up.

This prompt covers **Step 4 and Step 5** from the demo guide:
- Trigger the `healthcheckagent` subagent manually.
- Force a real anomaly (CPU or Memory) so the agent has something to detect.

The demo lives in `demos/AzureHealthCheck/`.

## Step 0 — Verify the demo is ready to run
From repo root:
```bash
source scripts/load-env.sh

# Confirm you’re logged into the right subscription
az account show -o table

# Confirm Octopets is deployed (Container Apps should be Running)
az containerapp list -g "$OCTOPETS_RG_NAME" -o table

# Confirm the SRE Agent exists and is running
az resource show \
   -g "$SRE_AGENT_RG_NAME" \
   -n "$SRE_AGENT_NAME" \
   --resource-type Microsoft.App/agents \
   --query "{name:name, powerState:properties.powerState, runningState:properties.runningState, endpoint:properties.agentEndpoint}" \
   -o json
```

If any of the required env vars are missing or Teams alerts aren’t configured yet, run the setup prompt first:
- `/.github/prompts/AzureHealthCheckSetup.prompt.md`

## Step 4 — Trigger the health check now (Portal)
1) In Azure Portal, open the **Azure SRE Agent** resource.
2) Go to **Subagent Builder**.
3) Select the subagent named `healthcheckagent`.
4) Click **Run Now** to trigger an immediate execution.
5) Monitor execution:
   - Open **Execution History** for the run.
   - Review logs for resource discovery and metric queries.
   - Note whether anomalies were detected.

## Step 5 — Force a real anomaly (recommended)
This lab’s easiest way to create a detectable anomaly is to enable an Octopets backend injector and generate traffic so Azure Monitor has measurable CPU/memory impact.

### Prerequisites
- Octopets is deployed and reachable.
- Your `.env` includes `OCTOPETS_RG_NAME`, `OCTOPETS_API_URL`, and `OCTOPETS_FE_URL`.

### Option A — CPU anomaly (fast, safe)
From repo root:
```bash
source scripts/load-env.sh
./scripts/61-enable-cpu-stress.sh
./scripts/60-generate-traffic.sh 15
```
Wait ~5–15 minutes for metrics aggregation, then run the `healthcheckagent` subagent again in the portal (**Run Now**).

Cleanup:
```bash
source scripts/load-env.sh
./scripts/62-disable-cpu-stress.sh
```

### Option B — Memory anomaly (more aggressive)
From repo root:
```bash
source scripts/load-env.sh
./scripts/63-enable-memory-errors.sh
./scripts/60-generate-traffic.sh 10
```
Wait ~5–15 minutes, then run the `healthcheckagent` subagent again (**Run Now**).

Cleanup:
```bash
source scripts/load-env.sh
./scripts/64-disable-memory-errors.sh
```

### If the agent reports “No anomalies detected”
- Extend traffic duration (e.g., `./scripts/60-generate-traffic.sh 20` or `30`).
- Re-run **Run Now** after another few minutes to allow metrics to roll up.

## Constraints
- Do not request or include any secrets (no webhook URLs, passwords, tokens).
- Do not modify vendored sources under `external/`.

## Success Criteria
- A manual run of `healthcheckagent` completes and appears in **Execution History**.
- After forcing CPU or memory load + waiting for rollup, a subsequent run identifies anomalies and produces a Teams alert (if the Teams connector is configured).
```
