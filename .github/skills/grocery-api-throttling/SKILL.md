---
name: grocery-api-throttling
description: >
  Trigger the Grocery SRE Demo supplier rate-limit incident on an already-deployed Azure
  Container Apps environment. Verifies the Grocery API and Web apps, runs the built-in
  smoke-and-trigger script, checks for intermittent 503 responses on inventory, and restores
  API scaling if needed. USE FOR: trigger Grocery SRE Demo, run Demo2, API throttling demo,
  supplier rate limit scenario, Grocery inventory 503 demo, smoke and trigger Grocery demo.
  DO NOT USE FOR: initial Grocery demo deployment (use 01-setup-demo.sh), Grafana MCP
  troubleshooting, or generic Container Apps debugging.
---

# Grocery API Throttling - Demo Skill

Run the Grocery SRE Demo incident scenario that induces intermittent `503` responses from the
inventory endpoint by pinning the API Container App to a single replica and repeatedly hitting
the supplier-backed inventory path.

## Working directory

Always run commands from the Grocery demo directory:

```bash
cd /workspaces/AzSreAgentLab/demos/GrocerySreDemo
```

## Step 1: Fast prerequisite check

Confirm Azure CLI is authenticated and showing the intended subscription:

```bash
az account show -o table
```

Then move into the demo folder:

```bash
cd /workspaces/AzSreAgentLab/demos/GrocerySreDemo
```

## Step 2: Confirm demo inputs exist

This workflow expects `demo-config.json`, which is created by `scripts/01-setup-demo.sh`.

Check that the file exists:

```bash
ls -la demo-config.json
```

If present, print the non-secret values used by the demo:

```bash
python3 - <<'PY'
import json
j=json.load(open('demo-config.json'))
for k in ['ResourceGroupName','ApiContainerAppName','WebContainerAppName','ApiUrl','WebUrl','GrafanaEndpoint','SreAgentEndpoint','SreAgentPortalUrl']:
  print(f"{k}={j.get(k,'')}")
PY
```

## Step 3: Snapshot current API scaling

The trigger script pins the API to `min=max=1` for demo reliability. Capture the current values
first so the change can be reversed without guessing.

```bash
RG=$(python3 -c "import json; print(json.load(open('demo-config.json'))['ResourceGroupName'])")
API_APP=$(python3 -c "import json; print(json.load(open('demo-config.json'))['ApiContainerAppName'])")

SCALE_JSON=$(az containerapp show -g "$RG" -n "$API_APP" \
  --query "{min:properties.template.scale.minReplicas,max:properties.template.scale.maxReplicas}" -o json)

echo "$SCALE_JSON"

ORIG_MIN=$(python3 -c "import json,sys; j=json.load(sys.stdin); print('' if j['min'] is None else j['min'])" <<<"$SCALE_JSON")
ORIG_MAX=$(python3 -c "import json,sys; j=json.load(sys.stdin); print('' if j['max'] is None else j['max'])" <<<"$SCALE_JSON")

export RG API_APP ORIG_MIN ORIG_MAX
printf 'Captured original scale: min=%s max=%s\n' "${ORIG_MIN:-<unset>}" "${ORIG_MAX:-<unset>}"
```

## Step 4: Trigger the demo

Run the built-in script that:

- smoke-tests `/health` and `/api/products`
- pins the API app to one replica
- repeatedly calls `GET /api/products/PROD001/inventory`
- reports how many `503` responses were observed

```bash
./scripts/03-smoke-and-trigger.sh
```

Expected output includes:

- `[OK] API /health OK`
- `[OK] Web /health OK`
- `[OK] API /api/products OK`
- `Observed 503 count: <n>`

Non-zero is ideal. Zero can still happen if the environment is temporarily healthy or the rate
limit condition does not surface during that run.

## Step 5: Verify the symptom manually

If you want to re-check after the script completes, probe the inventory endpoint directly:

```bash
API_URL=$(python3 -c "import json; print(json.load(open('demo-config.json'))['ApiUrl'].rstrip('/'))")

for i in {1..20}; do
  code=$(curl -sS -o /dev/null -w "%{http_code}" "$API_URL/api/products/PROD001/inventory")
  echo "$i $code"
  sleep 0.2
done
```

Intermittent `503` responses confirm the scenario is active.

## Step 6: Restore API scaling

If you captured `ORIG_MIN` and `ORIG_MAX` in Step 3, restore those values directly:

```bash
if [[ -n "${ORIG_MIN:-}" && -n "${ORIG_MAX:-}" ]]; then
  az containerapp update -g "$RG" -n "$API_APP" --min-replicas "$ORIG_MIN" --max-replicas "$ORIG_MAX"
elif [[ -n "${ORIG_MIN:-}" ]]; then
  az containerapp update -g "$RG" -n "$API_APP" --min-replicas "$ORIG_MIN"
elif [[ -n "${ORIG_MAX:-}" ]]; then
  az containerapp update -g "$RG" -n "$API_APP" --max-replicas "$ORIG_MAX"
else
  echo "Original scale values were unset. Choose explicit restore values before updating."
fi
```

If you did not capture them, query the current scale again and restore with explicit values you
know are correct for the environment.

## Fallback when demo-config.json is missing

Do not guess URLs or resource names.

Either recreate the config by running setup:

```bash
cd /workspaces/AzSreAgentLab/demos/GrocerySreDemo
./scripts/01-setup-demo.sh
```

Or identify the correct API and Web endpoints from Azure first, then run the manual verification
loop with those values.

## Constraints

- Do not request or print secrets, tokens, passwords, or connection strings
- Prefer the built-in script over ad hoc command sequences
- Do not require local Docker
- Keep the environment reversible by capturing and restoring scale values

## Success criteria

- `03-smoke-and-trigger.sh` completes successfully
- The inventory endpoint shows intermittent `503` responses, or the script reports observed failures
- API scaling can be restored to the pre-demo values
