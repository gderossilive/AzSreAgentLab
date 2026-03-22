---
name: grubify-incident
description: >
  Run the Grubify Incident demo (Act 1: IT Operations). Triggers a memory leak in the Grubify
  container app, then observes the SRE Agent autonomously detect the HTTP 5xx alert, diagnose
  OOM as root cause, and remediate. USE FOR: break grubify app, trigger memory leak, run incident
  demo, Demo4, OOM simulation, SRE Agent remediation demo. DO NOT USE FOR: issue triage
  (use grubify-issue-triage), deploying grubify (use azd up), GitHub integration.
---

# Grubify Incident — Demo Skill

Run **Act 1: IT Operations** for the GrubifyIncidentLab demo. Trigger a memory leak in Grubify,
then watch the SRE Agent autonomously detect the HTTP 5xx alert, diagnose OOM as root cause,
and remediate.

## Working directory

Always run commands from the GrubifyIncidentLab demo directory:

```bash
cd /workspaces/AzSreAgentLab/demos/GrubifyIncidentLab
```

## Step 1: Source environment values

```bash
echo "APP_URL=$(azd env get-value CONTAINER_APP_URL 2>/dev/null)"
echo "RG=$(azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null)"
echo "AGENT=$(azd env get-value SRE_AGENT_NAME 2>/dev/null)"
echo "AGENT_ENDPOINT=$(azd env get-value SRE_AGENT_ENDPOINT 2>/dev/null)"
```

All four values must be set.

## Step 2: Verify prerequisites

### 2a) Grubify is healthy

```bash
APP_URL=$(azd env get-value CONTAINER_APP_URL 2>/dev/null)
curl -s -o /dev/null -w "Health: HTTP %{http_code}\n" "${APP_URL}/health"
curl -s -o /dev/null -w "Restaurants: HTTP %{http_code}\n" "${APP_URL}/api/restaurants"
```

`/api/restaurants` must return HTTP 200. `/health` may return 404 if the app has no health endpoint — that is acceptable as long as the API endpoints work.

### 2b) SRE Agent is Autonomous

```bash
RG=$(azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null)
AGENT=$(azd env get-value SRE_AGENT_NAME 2>/dev/null)
az resource show -g "$RG" -n "$AGENT" \
  --resource-type Microsoft.App/agents \
  --query '{mode:properties.actionConfiguration.mode, accessLevel:properties.actionConfiguration.accessLevel}' -o json
```

Must show `mode: autonomous`.

## Step 3: Trigger the memory leak

```bash
./scripts/break-app.sh
```

This sends 200 rapid POST requests to `/api/cart/demo-user/items`, flooding the in-memory cart
until the container approaches its 1Gi memory limit. Expect errors in later requests as memory
pressure builds.

## Step 4: Wait for alert + agent investigation

- Wait **5-8 minutes** for memory pressure to build and Azure Monitor to fire the HTTP 5xx alert
- Direct the user to open https://sre.azure.com → **Incidents** to watch the agent in real time

### What the agent does autonomously

1. Queries container logs for error patterns using KQL
2. Checks memory/CPU metrics via Azure Monitor
3. Searches the knowledge base for the HTTP 500 runbook
4. Identifies OOM / memory leak as root cause
5. Executes remediation (restart or scale the container)
6. Generates Python charts as evidence
7. Stores findings in memory for future incident correlation

## Step 5: Verify recovery

After the agent remediates:

```bash
APP_URL=$(azd env get-value CONTAINER_APP_URL 2>/dev/null)
curl -s -o /dev/null -w "Restaurants: HTTP %{http_code}\n" "${APP_URL}/api/restaurants"
```

Should return HTTP 200.

## Reset (if needed)

To manually reset the demo without waiting for the agent, restart the active revision:

```bash
RG=$(azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null)
CA_NAME=$(az containerapp list -g "$RG" --query "[?contains(name,'grubify')&&!contains(name,'fe')].name" -o tsv)
REVISION=$(az containerapp revision list -g "$RG" -n "$CA_NAME" --query '[0].name' -o tsv)
az containerapp revision restart -g "$RG" -n "$CA_NAME" --revision "$REVISION"
```

## Success criteria

- [ ] `break-app.sh` completes with errors in the final requests (memory pressure)
- [ ] SRE Agent portal shows an incident being investigated
- [ ] Agent identifies memory leak / OOM as root cause
- [ ] Container app recovers (HTTP 200 on API endpoints)

## Constraints

- Do not manually restart the container — let the agent remediate
- This demo does not require GitHub integration
