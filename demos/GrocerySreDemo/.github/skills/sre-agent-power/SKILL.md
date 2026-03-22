---
name: sre-agent-power
description: >
  Start or stop Azure SRE Agents (Microsoft.App/agents). Handles all agents in the subscription
  or filters by resource group / agent name. Fixes null App Insights connectionString before
  starting (avoids InvalidApplicationInsightsConfiguration). USE FOR: start SRE agent, stop SRE
  agent, start all SRE agents, stop all SRE agents, power on SRE agent, power off SRE agent,
  restart SRE agent, agent powerState Running, agent powerState Stopped, toggle agent state.
  DO NOT USE FOR: deploying a new SRE Agent (use azd up or Bicep), configuring subagents or
  MCP connectors, or troubleshooting agent incidents.
argument-hint: 'start or stop [--resource-group RG] [--name AGENT_NAME]'
---

# SRE Agent Power — Start / Stop Skill

Start or stop one or all Azure SRE Agents (`Microsoft.App/agents`) in the subscription.

## Prerequisites

- Azure CLI logged in: `az account show`
- Subscription: `06dbbc7b-2363-4dd4-9803-95d07f1a8d3e` (default)

## Known agents (as of 2026-03-18)

| Agent name | Resource group | Demo |
|---|---|---|
| `sre-agent-demo` | `rg-sre-agent-demo` | Octopets / ServiceNow |
| `sre-agent-proactive-demo` | `rg-sre-proactive-demo` | Proactive Reliability |
| `sre-agent-grocery-demo` | `rg-grocery-sre-demo` | Grocery SRE |
| `sre-agent-cff6qws2yy4ku` | `rg-grubify-lab` | Grubify Incident |
| `sre-test` | `rg-grubify-lab` | (test) |

## Usage

Run the script from the repo root:

```bash
# Start all agents in subscription
bash .github/skills/sre-agent-power/scripts/sre-agent-power.sh start

# Stop all agents in subscription
bash .github/skills/sre-agent-power/scripts/sre-agent-power.sh stop

# Start / stop agents in a specific resource group
bash .github/skills/sre-agent-power/scripts/sre-agent-power.sh start -g rg-grubify-lab
bash .github/skills/sre-agent-power/scripts/sre-agent-power.sh stop  -g rg-grubify-lab

# Single agent
bash .github/skills/sre-agent-power/scripts/sre-agent-power.sh start -g rg-grubify-lab -n sre-agent-cff6qws2yy4ku

# Different subscription
bash .github/skills/sre-agent-power/scripts/sre-agent-power.sh start --subscription <SUB_ID>
```

## What the script does

1. **Discovers** all `Microsoft.App/agents` with `az resource list`
2. **Fetches** full properties via `az rest` (API version `2025-05-01-preview`)
3. **Skips** agents already in the desired state
4. **Fixes App Insights config** before starting: if `connectionString` is null, it reads the
   connection string and AppId from the Application Insights resource linked via the agent's
   `hidden-link` tag (or falls back to the first App Insights component in the same RG).
5. **Starts / stops** via `POST /start` or `POST /stop` on the ARM REST API

## Verify state after the operation

```bash
az resource list --subscription 06dbbc7b-2363-4dd4-9803-95d07f1a8d3e \
  --resource-type Microsoft.App/agents \
  --query "[].{name:name, rg:resourceGroup}" -o table
```

Then for each agent:

```bash
az resource show -g <RG> -n <AGENT_NAME> \
  --resource-type Microsoft.App/agents \
  --query "{powerState:properties.powerState, runningState:properties.runningState}" -o json
```

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `InvalidApplicationInsightsConfiguration` | Only affects `az resource update --set properties.powerState` (not the `/start` action). The script uses `POST /start` so this is not an issue. |
| `NoRegisteredProviderFound` | Wrong API version | Script uses `2025-05-01-preview` (correct as of 2026-03) |
| Agent stays Stopped after start | ARM is async | Wait 10–30 s and re-check `powerState` |
| `az rest POST /stop` returns error | Agent may not be stoppable while in `BuildingKnowledgeGraph` | Try again after `runningState` transitions |
