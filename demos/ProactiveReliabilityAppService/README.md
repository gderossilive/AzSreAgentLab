# Proactive Reliability Demo (App Service Slot Swap)

This demo is a standalone **App Service** version of the upstream SRE Agent “proactive reliability” sample.

Goal: intentionally deploy “bad” code via **slot swap**, have **Azure SRE Agent** detect the response-time regression using **Application Insights** vs a stored **baseline**, then autonomously **swap back** to recover.

- Dedicated resource group for this demo (separate from Octopets)
- App + SRE Agent deployed **in the same RG**
- Uses **App Service slots** (`production` + `staging`)

> Notes
> - Region default is `swedencentral` to match SRE Agent preview constraints used in this lab.
> - No secrets are stored in this repo. Any Teams/GitHub/Email connector configuration is done in the portal.

## What gets deployed

- App Service + App Service Plan
- `staging` slot
- Log Analytics workspace + Application Insights
- Activity Log Alert: triggers when `Microsoft.Web/sites/slots/slotsswap/action` succeeds

The alert is used to trigger an **Incident trigger** in the SRE Agent portal.

## Workflows

This demo supports two complementary reliability workflows:

### 1. Reactive Recovery (Post-Deployment)
**Goal**: Automatically detect and remediate performance regressions that reach production.

**Flow**:
1. Slot swap occurs (staging → production)
2. Activity Log Alert fires
3. SRE Agent's `DeploymentHealthCheck` subagent:
   - Queries Application Insights for current production response time
   - Compares against stored baseline
   - If regression ≥20%, executes automatic rollback (swap back)
   - Creates GitHub issue with root cause analysis
   - Posts summary to Teams

**Use Case**: Safety net for unexpected production degradation.

### 2. Proactive Prevention (Pre-Deployment) — NEW
**Goal**: Validate staging slot performance **before** promoting to production to prevent regressions.

**Flow**:
1. Developer/operator requests pre-swap validation (manual or automated)
2. SRE Agent's `PreSwapHealthGate` subagent:
   - Queries Application Insights for staging slot response time (last 5 minutes)
   - Compares against stored baseline
   - If deviation ≥20%, **REJECTS** the swap and files GitHub issue
   - If deviation <20%, **APPROVES** the swap
   - Posts decision to Teams

**Use Case**: Gate deployments to prevent known performance issues from reaching production.

**Recommended Setup**:
- Manual trigger: Run on-demand before planned production deployments
- Automated trigger: Integrate with CI/CD pipeline as a deployment gate
- Generate load to staging slot (5+ requests) before validation to ensure sufficient data

## Prerequisites

- Azure CLI authenticated: `az login`
- Bash (this repo’s demo scripts are bash)
- .NET SDK (the sample app is .NET)
- Azure subscription permissions:
  - you (human) need enough permissions to deploy the infra and app (Contributor on the demo RG is fine)
  - the SRE Agent must be deployed in **Privileged** mode to run the slot swap remediation command

## Quickstart

### 1) Choose names

- Resource group: `rg-sre-proactive-demo`
- App Service name: must be globally unique, e.g. `sreproactive-<alias>-<random>`
- Region: `swedencentral`

### 2) Deploy infra + app versions

Run:

```bash
./scripts/01-setup-demo.sh
```

This script will:
- Create the RG (if needed)
- Deploy infra via Bicep
- Build + deploy **GOOD** code to production
- Build + deploy **BAD** code to the `staging` slot
- Write `demo-config.json` with discovered outputs

Optional: override defaults

```bash
./scripts/01-setup-demo.sh \
  --resource-group "rg-sre-proactive-demo" \
  --app-service-name "sreproactive-<unique>" \
  --location "swedencentral" \
  --subscription-id "$AZURE_SUBSCRIPTION_ID"
```

### 3) Deploy the SRE Agent (same RG)

1. Open https://sre.azure.com
2. Create a new SRE Agent deployment in the same RG you used above
3. Set **Mode = Privileged**

### 4) Configure connectors (portal)

This demo’s subagents can post to Teams, file GitHub issues, and send email.
Configure the connectors you want in the SRE Agent portal (Connectors).

You can start with just **no-op** on Teams/GitHub/Email by removing those tools from the subagent definitions, but the templates here assume you will configure them.

### 5) Create subagents + triggers

Use the YAML templates in `SubAgents/` as a starting point:

- `SubAgents/AvgResponseBaseline.yaml` — Computes and stores baseline response time
- `SubAgents/DeploymentHealthCheck.yaml` — Reactive health check after swap (detects regression and swaps back)
- `SubAgents/PreSwapHealthGate.yaml` — **NEW**: Proactive validation before swap (prevents deploying regressions)
- `SubAgents/DeploymentReporter.yaml` — Daily deployment summary reporter

You must replace placeholders:
- `<YOUR_SUBSCRIPTION_ID>`
- `<YOUR_RESOURCE_GROUP>`
- `<YOUR_APP_SERVICE_NAME>`
- `<YOUR_APP_INSIGHTS_APP_ID>`
- `<YOUR_APP_INSIGHTS_NAME>`
- `<YOUR_TEAMS_CHANNEL_URL>` (optional if using Teams)
- `<YOUR_EMAIL_ADDRESS>` (optional if using email)

Helpful commands:

```bash
az webapp show -g rg-sre-proactive-demo -n <appServiceName> --query id -o tsv
az monitor app-insights component show -g rg-sre-proactive-demo -a <appInsightsName> --query appId -o tsv
```

Recommended triggers:

- Scheduled trigger `BaselineTask` (every 15m) → subagent `AvgResponseTime`
- **Manual/On-Demand trigger `PreSwapValidation`** → subagent `PreSwapHealthGate` — Run before manual swaps to validate staging performance
- Incident trigger `Swap Alert` (title contains `slot swap`) → subagent `DeploymentHealthCheck`
- Scheduled trigger `ReporterTask` (daily) → subagent `DeploymentReporter`

### 6) Run the live demo

```bash
./scripts/02-run-demo.sh
```

Non-interactive runs (skip the ENTER prompt before swapping):

```bash
./scripts/02-run-demo.sh --yes
```

This will:
- swap `staging` → `production` (bad code to prod)
- generate load to produce telemetry
- wait for SRE Agent remediation (swap back)

### Demo Flow (End-to-End)

Typical session (end-to-end):

- Preparation (before any alert/incident)
  - If you're using Copilot Chat, you can run the prompt ` /RunProactiveReliabilityDemo ` to get a guided, end-to-end prep + run checklist (source: [.github/prompts/RunProactiveReliabilityDemo.prompt.md](.github/prompts/RunProactiveReliabilityDemo.prompt.md)).
  - Confirm `demo-config.json` exists and points to the expected App Service + `staging` slot.
  - Confirm baseline state: production is faster than staging on the probe path (default `/api/products`).
  - Confirm Azure CLI access: logged in and the selected subscription matches `demo-config.json`.
  - Confirm the SRE Agent is ready to act:
    - Deployed in the same resource group as the App Service
    - Access level is **Privileged** and action mode is **Autonomous**
    - Required subagents + triggers are configured (baseline writer + swap-alert health check)
    - A fresh baseline artifact exists (commonly `baseline.txt`)

  Quick prep commands (safe, no secrets):

  ```bash
  cd /workspaces/AzSreAgentLab/demos/ProactiveReliabilityAppService

  # Show current demo values
  python3 - <<'PY'
  import json
  j=json.load(open('demo-config.json'))
  for k in ['SubscriptionId','Location','ResourceGroupName','AppServiceName','ProductionUrl','StagingUrl','ApplicationInsightsName']:
    print(f"{k}={j.get(k)}")
  PY

  # Sanity check: prod should be faster than staging
  PROD=$(python3 -c "import json;print(json.load(open('demo-config.json'))['ProductionUrl'].rstrip('/'))")
  STAGING=$(python3 -c "import json;print(json.load(open('demo-config.json'))['StagingUrl'].rstrip('/'))")
  curl -sS -o /dev/null -w "prod code=%{http_code} time=%{time_total}s\n" "$PROD/api/products"
  curl -sS -o /dev/null -w "staging code=%{http_code} time=%{time_total}s\n" "$STAGING/api/products"

  # Confirm Azure context
  az account show --query '{subscriptionId:id, subscriptionName:name, tenantId:tenantId, user:user.name}' -o json

  # Confirm SRE Agent status in the demo RG
  DEMO_RG="$(python3 -c "import json;print(json.load(open('demo-config.json'))['ResourceGroupName'])")"
  az resource list -g "$DEMO_RG" --resource-type Microsoft.App/agents --query "[].name" -o tsv

  SRE_AGENT_NAME="$(az resource list -g "$DEMO_RG" --resource-type Microsoft.App/agents --query "[0].name" -o tsv)"
  az resource show -g "$DEMO_RG" -n "$SRE_AGENT_NAME" --resource-type Microsoft.App/agents \
    --query '{name:name, endpoint:properties.agentEndpoint, actionMode:properties.actionConfiguration.mode, accessLevel:properties.actionConfiguration.accessLevel, runningState:properties.runningState}' \
    -o json
  ```
- Run
  - Swap `staging` → `production` and generate load (typically via `./scripts/02-run-demo.sh --yes`).
- Detection + triage (after the incident fires)
  - The agent receives an incident like “Detected Sev2 alert: Proactive Reliability High Response Time” for the target App Service.
  - It queries Application Insights over the incident window (for example, the last 5 minutes) to compute current average response time.
  - It retrieves the most recent stored baseline (for example from `baseline.txt`).
  - It compares timestamps (current must be newer) and response time vs baseline (for example, >20% regression threshold) to decide whether remediation is required.
- Remediation + verification
  - It verifies the app/slot state (staging slot present; app reachable).
  - It executes the remediation slot swap (swap `staging` → `production`, or swap back depending on which slot is healthy).
  - It re-queries Application Insights to confirm improvement.
- Comms + closure
  - It posts a short deployment/health summary (for example to Teams) with links/metrics.
  - Optionally, it opens a GitHub issue capturing findings and recommendations.
  - It records an incident closure note (for example: “Impact cleared. App Service response time back to baseline; no residual impact.”).

ASCII flow (typical):

```text
  +------------------------------+
  | Preparation checklist         |
  | - demo-config.json            |
  | - prod faster than staging    |
  | - az login + right sub        |
  | - agent ready + baseline.txt  |
  +--------------+---------------+
                 |
                 v
  +------------------------------+
  | Detected Sev2 slot-swap alert |
  +--------------+---------------+
                 |
                 v
  +------------------------------+
  | Query Application Insights   |
  | (current avg response time)  |
  +--------------+---------------+
                 |
                 v
  +------------------------------+
  | Retrieve baseline.txt        |
  | (baseline avg + timestamp)   |
  +--------------+---------------+
                 |
                 v
        +----------------------+
        | Compare current vs   |
        | baseline + threshold |
        +---------+------------+
                  |
        +---------+---------+
        |                   |
        v                   v
  +----------------+  +-----------------------+
  | No remediation |  | Remediation required  |
  | (monitor only) |  +----------+------------+
  +--------+-------+             |
           |                     v
           |          +-----------------------+
           |          | Verify slots/app      |
           |          | (prod/staging health) |
           |          +----------+------------+
           |                     |
           |                     v
           |          +-----------------------+
           |          | Execute slot swap     |
           |          +----------+------------+
           |                     |
           |                     v
           |          +-----------------------+
           |          | Re-query App Insights |
           |          | (confirm improvement) |
           |          +----------+------------+
           |                     |
           v                     v
  +----------------+   +----------------------+
  | Post summary   |   | Post summary         |
  | (Teams/email)  |   | + GitHub issue (opt) |
  +----------------+   +----------------------+
```

Useful options:

```bash
# Validate prod/staging probes without swapping
./scripts/02-run-demo.sh --dry-run --no-wait

# Use a different probe path if needed
./scripts/02-run-demo.sh --probe-path /api/products --dry-run
```

### Using Pre-Swap Health Gate (Proactive Validation)

To validate staging slot performance **before** swapping to production:

#### Option 1: Manual Validation via SRE Agent Portal

1. In the SRE Agent portal, navigate to the `PreSwapValidation` trigger
2. Generate load to staging slot to ensure sufficient telemetry:
   ```bash
   # Get staging URL from demo config
   STAGING=$(python3 -c "import json;print(json.load(open('demo-config.json'))['StagingUrl'].rstrip('/'))")
   
   # Generate 10 requests to staging
   for i in {1..10}; do
     curl -sS -o /dev/null -w "staging: %{http_code} %{time_total}s\n" "$STAGING/api/products"
     sleep 1
   done
   ```
3. Manually trigger the `PreSwapValidation` trigger in the SRE Agent portal
4. Review the validation result in Teams/email:
   - **APPROVE SWAP**: Staging performance is within acceptable range (<20% deviation)
   - **REJECT SWAP**: Staging has performance regression (≥20% deviation) — do not deploy

#### Option 2: Scripted Validation

Create a helper script to automate pre-swap validation:

```bash
#!/usr/bin/env bash
# validate-before-swap.sh

set -euo pipefail

config_path="./demo-config.json"
staging_url="$(python3 -c "import json;print(json.load(open('$config_path'))['StagingUrl'].rstrip('/'))")"

echo "Generating load to staging slot for validation..."
for i in {1..10}; do
  curl -sS -o /dev/null -w "Request $i: %{time_total}s\n" "$staging_url/api/products"
  sleep 1
done

echo ""
echo "Load generation complete."
echo "Now trigger the PreSwapValidation in SRE Agent portal and wait for approval/rejection."
echo ""
echo "If APPROVED: Proceed with slot swap"
echo "If REJECTED: Investigate performance regression in staging before deploying"
```

#### Integration with CI/CD Pipelines

For automated gating, integrate the pre-swap validation into your deployment pipeline:

1. **Generate staging load**: Ensure Application Insights has recent staging telemetry
2. **Trigger validation**: Use SRE Agent API or manual trigger to run `PreSwapHealthGate`
3. **Wait for result**: Poll for validation completion
4. **Gate decision**:
   - If APPROVED → Proceed with `az webapp deployment slot swap`
   - If REJECTED → Cancel deployment, file issue, investigate

This prevents deploying known performance regressions to production.

### Optional: run via VS Code tasks

If you're using the dev container in VS Code, there are helper tasks under `.vscode/tasks.json`:

- `setup-proactive-reliability-demo`
- `show-proactive-demo-sre-agent`
- `run-proactive-reliability-demo`
- `reset-proactive-reliability-demo`

Use: Terminal → Run Task…

### 7) Reset back to baseline (optional)

If you swapped bad code into production (or aborted mid-run), reset the app back to the baseline state:

```bash
./scripts/03-reset-demo.sh
```

Notes:
- By default it probes production vs staging and only swaps if production looks worse.
- Use `--force-swap` if probing is inconclusive and you still want to swap.

## Troubleshooting: recovery timed out

If `./scripts/02-run-demo.sh` times out waiting for recovery, it usually means the alert/trigger/subagent/action chain did not execute (or the agent can’t act yet).

### 1) Confirm the SRE Agent can actually remediate

- In the SRE Agent portal, confirm **Mode = Privileged** and action mode is **Autonomous**.
- Confirm the agent is ready (some deployments stay in `BuildingKnowledgeGraph` for a while).

Safe CLI check (no secrets):

```bash
az resource show -g rg-sre-proactive-demo -n <SRE_AGENT_NAME> --resource-type Microsoft.App/agents \
  --query "{name:name, actionMode:properties.actionConfiguration.mode, accessLevel:properties.actionConfiguration.accessLevel, runningState:properties.runningState, endpoint:properties.agentEndpoint}" \
  -o json
```

### 2) Confirm the slot swap alert fired

- In Azure Portal: Activity log → filter `Microsoft.Web/sites/slots/slotsswap/action` and verify the swap succeeded.
- Confirm the Activity Log Alert exists and is scoped to `rg-sre-proactive-demo`.

Quick checks:

```bash
az monitor activity-log alert list -g rg-sre-proactive-demo -o table
az monitor activity-log list --resource-group rg-sre-proactive-demo \
  --max-events 30 \
  --query "[?contains(operationName.value, 'slotsswap')].[eventTimestamp, status.value, operationName.value, resourceGroupName]" \
  -o table
```

### 3) Confirm the incident trigger and subagent ran

- In the SRE Agent portal, verify the **incident trigger** fired from the slot swap alert.
- Confirm `DeploymentHealthCheck` executed and produced a remediation recommendation/action.

### 4) Confirm the baseline exists and is fresh

The health-check subagent compares current response time to a stored baseline (commonly `baseline.txt`).

- Verify the **scheduled baseline trigger** ran recently.
- Verify `baseline.txt` exists in the agent knowledge store.

### 5) Verify production is still slow (and reset if needed)

If you need to get back to a clean baseline state:

```bash
./scripts/03-reset-demo.sh
```

## Addressing Production Incidents

If you encounter a production incident (like the one documented in issue "App Service sreproactive-vscode-39596: Response time regression..."):

### Immediate Response (Reactive)
1. The `DeploymentHealthCheck` subagent should detect the regression and automatically swap back
2. Verify recovery in Application Insights
3. Review the GitHub issue created by the agent for root cause analysis

### Prevention for Future Deployments (Proactive)
1. **Use Pre-Swap Validation**: Before any future slot swaps, run the `PreSwapHealthGate` subagent
2. **Generate Staging Load**: Ensure staging has 5+ requests in the last 5 minutes before validation
3. **Review Validation Result**:
   - If REJECTED: Investigate and fix the performance issue before deploying
   - If APPROVED: Proceed with the swap
4. **Continuous Monitoring**: Keep the baseline updated (every 15 minutes) to detect drift

### Root Cause Investigation Checklist
When a regression is detected, investigate:
- [ ] Recent code changes in the degraded slot (git diff, PR review)
- [ ] Configuration changes (app settings, connection strings, scaling settings)
- [ ] External dependencies (database queries, API calls, third-party services)
- [ ] Resource utilization (CPU, memory, network)
- [ ] Application Insights dependency tracking for slow operations

The SRE Agent's `PreSwapHealthGate` and `DeploymentHealthCheck` subagents will help automate detection, but manual investigation may be needed for complex issues.

## Cleanup

```bash
az group delete -n rg-sre-proactive-demo --yes --no-wait
```

## Upstream reference

This demo is derived from the vendored upstream sample under:

- `external/sre-agent/samples/proactive-reliability/`
