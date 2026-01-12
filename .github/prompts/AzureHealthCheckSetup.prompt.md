```prompt
---
agent: agent
---
You are helping a contributor set up the **Azure Health Check with Teams Alerts** demo in this repo. The goal is to configure the required environment variables and run the **existing scripts** that validate Teams notifications for the health-check workflow.

This demo lives in `demos/AzureHealthCheck/`.

## Requirements
1) **Prerequisites check (fast)**
   - Confirm the lab is already deployed:
     - Octopets (frontend + backend) running on Azure Container Apps.
     - Azure SRE Agent deployed and running.
   - Provide copy/paste commands to verify:
     - `az account show`
     - `az containerapp list -g $OCTOPETS_RG_NAME -o table`
     - `az resource show -g $SRE_AGENT_RG_NAME -n $SRE_AGENT_NAME --resource-type Microsoft.App/agents --query properties.powerState -o tsv`

2) **Teams webhook setup (no secrets in repo)**
   - Instruct the user to create a Teams webhook via Power Automate (high level only).
   - Require them to store the webhook URL in `.env` as `TEAMS_WEBHOOK_URL`.
   - Emphasize:
     - Never commit `.env` or the webhook URL.
     - Use `scripts/set-dotenv-value.sh` instead of editing manually.

3) **Script-driven setup flow (exact commands)**
   Provide the exact command sequence from repo root:
   - `source scripts/load-env.sh`
   - Set the Teams webhook URL:
     - `scripts/set-dotenv-value.sh "TEAMS_WEBHOOK_URL" "<PASTE_WEBHOOK_URL_HERE>"`
   - Reload env:
     - `source scripts/load-env.sh`
   - Test Teams webhook:
     - `./scripts/70-test-teams-webhook.sh`
   - Send a sample anomaly card:
     - `./scripts/71-send-sample-anomaly.sh`

   Include expected results:
   - A test message appears in the chosen Teams channel.
   - The sample anomaly card appears and resembles the demo’s described output.

4) **Link the demo’s subagent YAML and what to do with it**
   - Point to the YAML:
     - `demos/AzureHealthCheck/azurehealthcheck-subagent-simple.yaml`
   - Explain that this YAML is intended to be pasted into the Azure SRE Agent **Subagent Builder** in the Azure Portal.
   - Keep it practical:
     - what fields the user should edit (if any)
     - suggest a reasonable schedule (e.g., daily)
   - Do not invent portal URLs; keep navigation generic.

5) **Optional: generate baseline traffic**
   - If the user wants more realistic metrics to analyze, include:
     - `./scripts/60-generate-traffic.sh`
   - Keep it optional and clearly labeled.

## Constraints
- Do not modify vendored sources under `external/`.
- Do not add new scripts or tooling.
- Do not require Docker; use the existing script workflow.
- Do not include or request any secrets in outputs (no webhook URLs, passwords, tokens).

## Success Criteria
- `TEAMS_WEBHOOK_URL` is present in `.env` (uncommitted) and loaded.
- `scripts/70-test-teams-webhook.sh` succeeds.
- `scripts/71-send-sample-anomaly.sh` successfully posts to Teams.
- The user is pointed to the correct YAML to configure the scheduled health-check subagent.

```