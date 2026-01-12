```prompt
---
agent: agent
---
You are helping a contributor set up and run the **ServiceNow Incident Automation** demo in this repo.

This demo lives in `demos/ServiceNowAzureResourceHandler/` and shows an end-to-end flow:
Azure Monitor alerts → (Logic App webhook) → ServiceNow incident → Azure SRE Agent subagent investigation.

## Requirements
1) **Prerequisites check (fast)**
   - Confirm the lab is already deployed:
     - Octopets running on Azure Container Apps.
     - Azure SRE Agent deployed.
   - Provide copy/paste commands to verify:
     - `az account show`
     - `az containerapp list -g $OCTOPETS_RG_NAME -o table`
     - `az resource show -g $SRE_AGENT_RG_NAME -n $SRE_AGENT_NAME --resource-type Microsoft.App/agents --query properties.powerState -o tsv`

2) **ServiceNow prerequisites (no secrets in repo)**
   - Require a ServiceNow developer instance.
   - Require these `.env` variables to be set (do not print actual values):
     - `SERVICENOW_INSTANCE` (instance name without `.service-now.com`, e.g. `dev12345`)
     - `SERVICENOW_USERNAME`
     - `SERVICENOW_PASSWORD`
   - Emphasize:
     - Never commit `.env` or credentials.
     - Use `scripts/set-dotenv-value.sh` to set values.

3) **Script-driven deployment flow (exact commands)**
   Provide the exact command sequence from repo root:
   - Load env:
     - `source scripts/load-env.sh`
   - Set ServiceNow values (examples only, do not hardcode):
     - `scripts/set-dotenv-value.sh "SERVICENOW_INSTANCE" "<INSTANCE_NAME>"`
     - `scripts/set-dotenv-value.sh "SERVICENOW_USERNAME" "<USERNAME>"`
     - `scripts/set-dotenv-value.sh "SERVICENOW_PASSWORD" "<PASSWORD>"`
   - Reload env:
     - `source scripts/load-env.sh`
   - Deploy the Logic App webhook (writes `SERVICENOW_WEBHOOK_URL` back into `.env`):
     - `./scripts/50-deploy-logic-app.sh`
   - Deploy Azure Monitor alert rules + action group pointing at the webhook:
     - `./scripts/50-deploy-alert-rules.sh`

   Include expected results:
   - `50-deploy-logic-app.sh` prints a Logic App callback URL and updates `.env` with `SERVICENOW_WEBHOOK_URL`.
   - `50-deploy-alert-rules.sh` prints the created action group and alert rule names.

4) **Link the demo’s subagent YAML and what to do with it**
   - Point to the YAML:
     - `demos/ServiceNowAzureResourceHandler/servicenow-subagent-simple.yaml`
   - Explain it should be pasted into the Azure SRE Agent **Subagent Builder** in the Azure Portal.
   - Keep navigation generic; do not invent portal URLs.
   - Mention the trigger cadence should be relatively frequent for demos (e.g., every 2 minutes) if/when configuring a scheduled trigger.

5) **Pointers to IaC assets used by scripts (for understanding only)**
   - Logic App template:
     - `demos/ServiceNowAzureResourceHandler/servicenow-logic-app.bicep`
   - Alert rules template:
     - `demos/ServiceNowAzureResourceHandler/octopets-alert-rules.bicep`

## Constraints
- Do not modify vendored sources under `external/`.
- Do not add new scripts or tooling.
- Do not require Docker.
- Do not include or request secrets in outputs.

## Success Criteria
- ServiceNow variables are set in `.env` (uncommitted) and loadable via `source scripts/load-env.sh`.
- `./scripts/50-deploy-logic-app.sh` succeeds and updates `.env` with `SERVICENOW_WEBHOOK_URL`.
- `./scripts/50-deploy-alert-rules.sh` succeeds and creates alert rules in the Octopets resource group.
- The user is pointed to the correct YAML to configure the ServiceNow subagent.
- The user can trigger a condition (memory errors or CPU stress), generate traffic, and observe the workflow progress (alerts/ServiceNow incidents) using the provided scripts.
