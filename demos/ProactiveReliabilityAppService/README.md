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

- `SubAgents/AvgResponseBaseline.yaml`
- `SubAgents/DeploymentHealthCheck.yaml`
- `SubAgents/DeploymentReporter.yaml`

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
- Incident trigger `Swap Alert` (title contains `slot swap`) → subagent `DeploymentHealthCheck`
- Scheduled trigger `ReporterTask` (daily) → subagent `DeploymentReporter`

### 6) Run the live demo

```bash
./scripts/02-run-demo.sh
```

This will:
- swap `staging` → `production` (bad code to prod)
- generate load to produce telemetry
- wait for SRE Agent remediation (swap back)

Useful options:

```bash
# Validate prod/staging probes without swapping
./scripts/02-run-demo.sh --dry-run --no-wait

# Use a different probe path if needed
./scripts/02-run-demo.sh --probe-path /api/products --dry-run
```

### 7) Reset back to baseline (optional)

If you swapped bad code into production (or aborted mid-run), reset the app back to the baseline state:

```bash
./scripts/03-reset-demo.sh
```

Notes:
- By default it probes production vs staging and only swaps if production looks worse.
- Use `--force-swap` if probing is inconclusive and you still want to swap.

## Cleanup

```bash
az group delete -n rg-sre-proactive-demo --yes --no-wait
```

## Upstream reference

This demo is derived from the vendored upstream sample under:

- `external/sre-agent/samples/proactive-reliability/`
