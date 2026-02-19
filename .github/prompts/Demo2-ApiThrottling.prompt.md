```prompt
---
agent: agent
---
You are helping a contributor **trigger the Grocery SRE Demo incident scenario** on the already-deployed Grocery environment (Azure Container Apps).

Your goal is to provide **safe, repeatable, copy/paste commands** to:
1) confirm the Grocery API + Web Container Apps are running,
2) trigger the supplier rate-limit scenario (intermittent `503` on inventory),
3) verify it happened,
4) optionally revert the API scaling change the trigger makes.

## Requirements

### 1) Prereqs check (fast)
- Ensure Azure CLI is authenticated:

  ```bash
  az account show -o table
  ```

- Move to the demo folder:

  ```bash
  cd demos/GrocerySreDemo
  ```

### 2) Confirm deployment inputs exist
This demo’s trigger script expects `demo-config.json` (created by `scripts/01-setup-demo.sh`).

- Check the config file:

  ```bash
  ls -la demo-config.json
  ```

- If it exists, print key fields (no secrets):

  ```bash
  python3 - <<'PY'
import json
j=json.load(open('demo-config.json'))
for k in ['ResourceGroupName','ApiContainerAppName','WebContainerAppName','ApiUrl','WebUrl','GrafanaEndpoint','SreAgentEndpoint','SreAgentPortalUrl']:
  print(f"{k}={j.get(k,'')}")
PY
  ```

### 3) (Optional but recommended) snapshot current API scaling
The trigger script pins the API to **1 replica** for demo reliability (`min=max=1`). Capture current values so you can restore afterwards.

```bash
RG=$(python3 -c "import json; print(json.load(open('demo-config.json'))['ResourceGroupName'])")
API_APP=$(python3 -c "import json; print(json.load(open('demo-config.json'))['ApiContainerAppName'])")

az containerapp show -g "$RG" -n "$API_APP" \
  --query "{name:name,min:properties.template.scale.minReplicas,max:properties.template.scale.maxReplicas}" -o json
```

### 4) Trigger the demo (preferred)
Run the built-in script that:
- smoke-tests `/health` and `/api/products`
- pins API scaling to 1 replica
- repeatedly hits `GET /api/products/PROD001/inventory` to induce intermittent `503`

```bash
cd demos/GrocerySreDemo
./scripts/03-smoke-and-trigger.sh
```

Expected output:
- `[OK] API /health OK`
- `[OK] Web /health OK`
- `[OK] API /api/products OK`
- `Observed 503 count: <n>` (non-zero is ideal; zero can happen if the environment is “too healthy” at that moment)

### 5) Verify the symptom quickly (manual curl)
If you want to re-check after the script completes:

```bash
API_URL=$(python3 -c "import json; print(json.load(open('demo-config.json'))['ApiUrl'].rstrip('/'))")

for i in {1..20}; do
  code=$(curl -sS -o /dev/null -w "%{http_code}" "$API_URL/api/products/PROD001/inventory")
  echo "$i $code"
  sleep 0.2
done
```

### 6) (Optional) Restore API scaling
Use the values you captured earlier (or choose reasonable defaults). Example restore to `min=1,max=5`:

```bash
RG=$(python3 -c "import json; print(json.load(open('demo-config.json'))['ResourceGroupName'])")
API_APP=$(python3 -c "import json; print(json.load(open('demo-config.json'))['ApiContainerAppName'])")

az containerapp update -g "$RG" -n "$API_APP" --min-replicas 1 --max-replicas 5
```

## Fallback (if demo-config.json is missing)
If `demo-config.json` is missing, do NOT guess URLs.

Either:
- Recreate it by running setup (may redeploy/update resources):

  ```bash
  cd demos/GrocerySreDemo
  ./scripts/01-setup-demo.sh
  ```

Or:
- Identify the API/Web URLs from Azure first (requires knowing the resource group, commonly `rg-grocery-sre-demo`), then run the manual curl loop above.

## Constraints
- Do not request or print secrets (tokens, passwords, connection strings).
- Prefer script-driven flow; do not require local Docker.
- Keep the demo reversible; include the scaling restore command.

## Success Criteria
- Trigger run completes.
- Inventory endpoint returns intermittent `503` (or the log indicates some failures were observed).
- API scaling is optionally restored to the pre-demo state.
```
````

`````prompt
