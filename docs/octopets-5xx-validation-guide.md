# Validation and Testing Guide for Octopets API 5xx Fix

## Pre-Deployment Validation

### 1. Bicep Syntax Validation

```bash
# Validate main.bicep
az bicep build --file infra/octopets/main.bicep

# Validate resources.bicep
az bicep build --file infra/octopets/resources.bicep
```

Expected result: No errors, JSON files generated successfully.

### 2. What-If Deployment (Non-Destructive)

```bash
source scripts/load-env.sh

az deployment sub what-if \
  -l "$AZURE_LOCATION" \
  -f infra/octopets/main.bicep \
  -p environmentName="$OCTOPETS_ENV_NAME" \
  -p location="$AZURE_LOCATION"
```

Expected result: Preview of resources that will be created/modified without actually deploying.

## Deployment Testing

### Option A: New Deployment (Recommended for Testing)

Deploy to a test environment first:

```bash
# Set test environment name
export OCTOPETS_ENV_NAME="octopets-test-lab"
export AZURE_LOCATION="swedencentral"
export AZURE_SUBSCRIPTION_ID="your-subscription-id"

# Deploy infrastructure
./scripts/30-deploy-octopets.sh

# Deploy containers
./scripts/31-deploy-octopets-containers.sh

# Verify health endpoints are accessible
OCTOPETS_API_URL=$(az containerapp show \
  -g "rg-${OCTOPETS_ENV_NAME}" \
  -n octopetsapi \
  --query "properties.configuration.ingress.fqdn" -o tsv)

curl -s "https://${OCTOPETS_API_URL}/health" | jq
```

Expected response:
```json
{
  "Status": "Healthy",
  "Timestamp": "2026-01-26T..."
}
```

### Option B: Update Existing Deployment (Production Fix)

Apply the fix to the existing production environment:

```bash
source scripts/load-env.sh

# Apply configuration fix
./scripts/70-fix-octopets-api-config.sh
```

## Post-Deployment Validation

### 1. Container App Configuration Check

```bash
source scripts/load-env.sh

# Get full configuration
az containerapp show \
  -g "$OCTOPETS_RG_NAME" \
  -n octopetsapi \
  -o json > /tmp/octopetsapi-config.json

# Verify key settings
cat /tmp/octopetsapi-config.json | jq '{
  minReplicas: .properties.template.scale.minReplicas,
  maxReplicas: .properties.template.scale.maxReplicas,
  envVars: .properties.template.containers[0].env | map(select(.name | IN("CPU_STRESS", "MEMORY_ERRORS", "OTEL_METRICS_EXPORTER", "OTEL_LOGS_EXPORTER"))),
  probes: .properties.template.containers[0].probes
}'
```

Expected output:
```json
{
  "minReplicas": 2,
  "maxReplicas": 10,
  "envVars": [
    {"name": "CPU_STRESS", "value": "false"},
    {"name": "MEMORY_ERRORS", "value": "false"},
    {"name": "OTEL_METRICS_EXPORTER", "value": "otlp"},
    {"name": "OTEL_LOGS_EXPORTER", "value": "otlp"}
  ],
  "probes": [
    {
      "type": "Liveness",
      "httpGet": {"path": "/health", "port": 8080, ...}
    },
    {
      "type": "Readiness",
      "httpGet": {"path": "/health", "port": 8080, ...}
    }
  ]
}
```

### 2. Health Endpoint Verification

```bash
# Get API URL
OCTOPETS_API_URL=$(az containerapp show \
  -g "$OCTOPETS_RG_NAME" \
  -n octopetsapi \
  --query "properties.configuration.ingress.fqdn" -o tsv)

# Test health endpoint
curl -s "https://${OCTOPETS_API_URL}/health" | jq

# Expected response: {"Status": "Healthy", "Timestamp": "..."}
```

### 3. Replica Count Verification

```bash
# Check running replicas
az containerapp revision list \
  -g "$OCTOPETS_RG_NAME" \
  -n octopetsapi \
  --query "[].{Name:name, Active:properties.active, Replicas:properties.replicas, Traffic:properties.trafficWeight}" \
  -o table
```

Expected: At least 2 replicas running for the active revision.

### 4. Metrics Monitoring (30-60 minutes)

Monitor in Azure Portal:

1. **Container Apps Metrics**:
   - Navigate to: Resource Group → octopetsapi → Metrics
   - Chart 1: Add metric "Requests" split by "Status Code"
     - Before fix: High 5xx count
     - After fix: Minimal/zero 5xx, increased 2xx
   - Chart 2: Add metric "Response Time"
     - Before fix: 1100-2200ms during spike
     - After fix: Should stabilize <500ms

2. **Application Insights**:
   - Navigate to: Resource Group → octopets_appinsights → Transaction search
   - Query: `requests | where timestamp > ago(1h)`
   - Expected: Requests now appearing (telemetry enabled)

3. **Health Probe Success Rate**:
   - Navigate to: octopetsapi → Revisions → Active revision → Metrics
   - Look for probe success/failure events in logs

### 5. Load Testing

Generate traffic to verify stability:

```bash
# Generate 100 requests
./scripts/60-generate-traffic.sh 100

# Monitor for errors
az containerapp logs show \
  -g "$OCTOPETS_RG_NAME" \
  -n octopetsapi \
  --tail 50 \
  --follow
```

Expected: No 5xx errors, healthy responses.

## Rollback Testing

Verify rollback procedures work:

```bash
# Enable fault injection (testing only!)
./scripts/63-enable-memory-errors.sh

# Verify error rate increases
# ...

# Disable fault injection
./scripts/64-disable-memory-errors.sh

# Verify error rate returns to normal
```

## Security Validation

### 1. Secrets Check

```bash
# Ensure no secrets in source control
cd /home/runner/work/AzSreAgentLab/AzSreAgentLab
grep -r "APPLICATIONINSIGHTS_CONNECTION_STRING" infra/ scripts/ docs/ | grep -v "value: appInsights"

# Expected: Only references to the variable, no actual connection strings
```

### 2. RBAC Verification

```bash
# Verify Container Apps have AcrPull role
az role assignment list \
  --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$OCTOPETS_RG_NAME/providers/Microsoft.ContainerRegistry/registries/*" \
  --query "[].{Principal:principalName, Role:roleDefinitionName}" \
  -o table
```

Expected: octopetsapi and octopetsfe managed identities have AcrPull role.

## Success Criteria

- [ ] Bicep files compile without errors
- [ ] Deployment completes successfully (infrastructure + containers)
- [ ] `/health` endpoint returns 200 OK
- [ ] 2 replicas running
- [ ] Health probes configured and passing
- [ ] CPU_STRESS=false, MEMORY_ERRORS=false
- [ ] OTEL_METRICS_EXPORTER=otlp, OTEL_LOGS_EXPORTER=otlp
- [ ] 5xx error rate <1% over 30 minutes
- [ ] Response time <500ms average
- [ ] Application Insights receiving telemetry
- [ ] No secrets committed to git
- [ ] Managed identities have correct RBAC

## Troubleshooting

### Issue: Health probe failures

**Symptoms**: Replicas restarting, CrashLoopBackOff  
**Diagnosis**:
```bash
az containerapp logs show -g "$OCTOPETS_RG_NAME" -n octopetsapi --tail 100
```
**Resolution**: Check if `/health` endpoint is responding on port 8080

### Issue: Bicep deployment fails

**Symptoms**: `az deployment sub create` returns errors  
**Diagnosis**:
```bash
az deployment sub list -l "$AZURE_LOCATION" --query "[0].properties.error" -o json
```
**Resolution**: Check error message, verify parameters, ensure quota available

### Issue: Containers not pulling images

**Symptoms**: Image pull errors in logs  
**Diagnosis**:
```bash
az role assignment list --assignee <container-app-principal-id> --all
```
**Resolution**: Ensure Container App managed identity has AcrPull role on ACR

### Issue: Still seeing 5xx errors after fix

**Symptoms**: Error rate remains high  
**Diagnosis**:
```bash
# Check if fault injection is still enabled
az containerapp show -g "$OCTOPETS_RG_NAME" -n octopetsapi \
  --query "properties.template.containers[0].env[?name=='CPU_STRESS' || name=='MEMORY_ERRORS']" \
  -o table
```
**Resolution**: Run `./scripts/70-fix-octopets-api-config.sh` again

---

For automated testing in CI/CD, consider adding:
- `az deployment sub validate` in pipeline
- Integration tests hitting `/health` endpoint
- Metrics-based rollback triggers
