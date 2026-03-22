---
agent: agent
---

# Demo4-GrubifyIncident

## Goal
Run **Act 1: IT Operations** — trigger a memory leak in Grubify, observe the SRE Agent autonomously detect the HTTP 5xx alert, diagnose OOM as root cause, and remediate.

## Inputs (fill at runtime)

Source values from the azd environment:

```bash
cd /workspaces/AzSreAgentLab/demos/GrubifyIncidentLab
echo "APP_URL=$(azd env get-value CONTAINER_APP_URL 2>/dev/null)"
echo "RG=$(azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null)"
echo "AGENT=$(azd env get-value SRE_AGENT_NAME 2>/dev/null)"
echo "AGENT_ENDPOINT=$(azd env get-value SRE_AGENT_ENDPOINT 2>/dev/null)"
```

## Prerequisites

### 1) Grubify is healthy

```bash
cd /workspaces/AzSreAgentLab/demos/GrubifyIncidentLab
APP_URL=$(azd env get-value CONTAINER_APP_URL 2>/dev/null)
curl -s -o /dev/null -w "Health: HTTP %{http_code}\n" "${APP_URL}/health"
curl -s -o /dev/null -w "Restaurants: HTTP %{http_code}\n" "${APP_URL}/api/restaurants"
```

Both should return HTTP 200.

### 2) SRE Agent is Autonomous

```bash
RG=$(azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null)
AGENT=$(azd env get-value SRE_AGENT_NAME 2>/dev/null)
az resource show -g "$RG" -n "$AGENT" \
  --resource-type Microsoft.App/agents \
  --query '{mode:properties.actionConfiguration.mode, accessLevel:properties.actionConfiguration.accessLevel}' -o json
```

Should show `mode: autonomous`.

## Execution

### Step 1: Trigger the memory leak

```bash
cd /workspaces/AzSreAgentLab/demos/GrubifyIncidentLab
./scripts/break-app.sh
```

This sends 200 rapid POST requests to `/api/cart/demo-user/items`, flooding the in-memory cart until the container approaches its 1Gi memory limit.

### Step 2: Wait for alert + agent investigation

- Wait **5-8 minutes** for memory pressure to build and Azure Monitor to fire the HTTP 5xx alert
- Open https://sre.azure.com → **Incidents** to watch the agent in real time

### Step 3: Observe agent actions

The agent will autonomously:
1. Query container logs for error patterns using KQL
2. Check memory/CPU metrics via Azure Monitor
3. Search the knowledge base for the HTTP 500 runbook
4. Identify OOM / memory leak as root cause
5. Execute remediation (restart or scale the container)
6. Generate Python charts as evidence
7. Store findings in memory for future incident correlation

### Step 4: Verify recovery

```bash
APP_URL=$(azd env get-value CONTAINER_APP_URL 2>/dev/null)
curl -s -o /dev/null -w "Health: HTTP %{http_code}\n" "${APP_URL}/health"
```

Should return HTTP 200 after agent remediation.

## Success Criteria
- `break-app.sh` completes with errors in the final requests (memory pressure)
- SRE Agent portal shows an incident being investigated
- Agent identifies memory leak / OOM as root cause
- Container app recovers (HTTP 200 on health check)

## Constraints
- Do not manually restart the container — let the agent remediate
- This act does not require GitHub integration
