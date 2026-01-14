````prompt
```prompt
---
agent: agent
---
You are helping a contributor **trigger a real anomaly on the two Azure Container Apps hosting Octopets**:
- `octopetsfe` (frontend)
- `octopetsapi` (backend)

Your goal is to provide **safe, repeatable, copy/paste commands** to:
1) confirm the Octopets Container Apps are running,
2) induce a temporary anomaly that impacts **both** apps (preferred) or at least the backend,
3) verify the anomaly is observable,
4) clean up completely.

## Requirements
1) **Prereqs check (fast)**
   - From repo root load env (no secrets printed):
     - `source scripts/load-env.sh`
   - Ensure Azure CLI is authenticated and scoped:
     - `./scripts/20-az-login.sh`
     - `az account show`
   - Confirm required variables exist:
     - `echo "$OCTOPETS_RG_NAME"`
     - `echo "$OCTOPETS_FE_URL"`
     - `echo "$OCTOPETS_API_URL"`
   - Confirm both Container Apps exist:

     ```bash
     az containerapp list -g "$OCTOPETS_RG_NAME" -o table
     az containerapp show -g "$OCTOPETS_RG_NAME" -n octopetsfe  --query '{name:name,status:properties.runningStatus}' -o table
     az containerapp show -g "$OCTOPETS_RG_NAME" -n octopetsapi --query '{name:name,status:properties.runningStatus}' -o table
     ```

2) **Trigger ONE real anomaly (recommended options)**

   **Option A — CPU/latency anomaly affecting BOTH apps (recommended)**
   This uses the built-in backend CPU injector plus higher request volume. The frontend is included because the traffic generator also hits the frontend endpoints.

   ```bash
   # 1) Enable backend CPU stress
   ./scripts/61-enable-cpu-stress.sh

   # 2) Generate traffic for 15 minutes
   # Start with ONE instance; if it’s not enough, run 2–3 in parallel.
   ./scripts/60-generate-traffic.sh 15
   ```

   If you need more load (be cautious), run in parallel:

   ```bash
   # Example: 2 parallel generators
   ./scripts/60-generate-traffic.sh 15 &
   ./scripts/60-generate-traffic.sh 15 &
   wait
   ```

   **Option B — Memory pressure anomaly (backend) + user traffic**

   ```bash
   ./scripts/63-enable-memory-errors.sh
   ./scripts/60-generate-traffic.sh 10
   ```

3) **Verify the anomaly (quick checks)**
   - Validate the injectors are set on the backend:

     ```bash
     az containerapp show -g "$OCTOPETS_RG_NAME" -n octopetsapi \
       --query "properties.template.containers[0].env[?name=='CPU_STRESS' || name=='MEMORY_ERRORS']" -o table
     ```

   - Capture current resource IDs (use these to open portal blades):

     ```bash
     FE_ID=$(az containerapp show -g "$OCTOPETS_RG_NAME" -n octopetsfe  --query id -o tsv)
     API_ID=$(az containerapp show -g "$OCTOPETS_RG_NAME" -n octopetsapi --query id -o tsv)
     echo "FE_ID=$FE_ID"
     echo "API_ID=$API_ID"
     ```

   - Observe symptoms:
     - `./scripts/60-generate-traffic.sh` prints ✓/✗ for frontend and API calls.
     - In Azure Portal, check metrics for both apps (CPU, memory, requests, 5xx) using the Container App Metrics blade.

   If the goal is to validate the scheduled health-check agent, instruct the user to:
   - wait ~5–15 minutes for metric rollups,
   - then manually run the `healthcheckagent` subagent (“Run now”) and confirm a Teams alert is sent.

4) **Cleanup (required)**

   ```bash
   # Disable backend injectors
   ./scripts/62-disable-cpu-stress.sh
   ./scripts/64-disable-memory-errors.sh
   ```

   Notes:
   - If you ran parallel traffic generators in the background, ensure they are stopped (they exit automatically after the duration, or use Ctrl+C).

## Constraints
- Do not request or print secrets (no webhook URLs, passwords, tokens).
- Prefer script-driven flow; do not require Docker.
- Keep the test short and reversible; include cleanup commands.
- Be explicit that higher load (parallel traffic) increases cost and resource pressure.

## Success Criteria
- The user can induce a measurable anomaly that impacts Octopets.
- The anomaly is observable (traffic errors/latency and/or Azure Monitor metrics).
- The user can revert to normal state via cleanup scripts.
```
````
