# Loki Query Reference — Grocery API (SRE Agent)

This is an **SRE Agent knowledge file** providing LogQL queries for diagnosing Grocery API issues in Loki.

---

## TL;DR for Agents

| Symptom                           | First Query |
|-----------------------------------|-------------|
| Intermittent 503 on `/inventory`  | `{app="grocery-api", level="error"} \| json \| errorCode="SUPPLIER_RATE_LIMIT_429"` |
| General errors                    | `{app="grocery-api", level="error"}` |
| Error spike detection             | `sum(rate({app="grocery-api", level="error"}[5m]))` |
| Identify error codes breakdown    | `sum by (errorCode) (count_over_time({app="grocery-api"} \| json \| errorCode!="" [15m]))` |

---

## Quick Facts

- **Primary label selector**: `{app="grocery-api"}`
- **Labels available**: `app`, `level`, `job`, `environment`
- **Log format**: JSON (pino) – always use `| json` to extract fields
- **Main error code**: `SUPPLIER_RATE_LIMIT_429` (supplier rate limiting → 503 to clients)

---

## Symptom → Query Decision Tree

### 1. Inventory requests returning 503

The Grocery API returns HTTP 503 when the upstream supplier returns 429 (rate limit).

```logql
# Confirm supplier rate limiting is the cause
{app="grocery-api", level="error"} | json | errorCode="SUPPLIER_RATE_LIMIT_429"

# Check how often this happens (rate per 5m)
sum(rate({app="grocery-api"} |= "SUPPLIER_RATE_LIMIT_429" [5m]))

# Count total events in the last 15 minutes
sum(count_over_time({app="grocery-api"} |= "SUPPLIER_RATE_LIMIT_429" [15m]))

# See retry timing suggested by supplier
{app="grocery-api", level="error"} | json | errorCode="SUPPLIER_RATE_LIMIT_429" | line_format "retryAfter={{.retryAfter}}s productId={{.productId}}"
```

### 2. General error investigation (any symptom)

```logql
# All errors
{app="grocery-api", level="error"}

# Error count over 1 hour
sum(count_over_time({app="grocery-api", level="error"}[1h]))

# Error rate trend (5m windows)
sum(rate({app="grocery-api", level="error"}[5m]))

# Errors grouped by error code
sum by (errorCode) (count_over_time({app="grocery-api"} | json | errorCode!="" [15m]))
```

### 3. Check for warning signals (pre-failure indicators)

```logql
# Warnings (may precede errors)
{app="grocery-api", level="warn"}

# Combined warn + error rate
sum(rate({app="grocery-api", level=~"warn|error"}[5m]))
```

### 4. Batch inventory failures

```logql
# Batch requests that hit rate limit mid-processing
{app="grocery-api"} | json | event="batch_inventory_rate_limited"

# Partial batch failures
{app="grocery-api"} | json | event="batch_inventory_partial_failure"
```

### 5. Product-specific investigation

```logql
# Errors for a specific product
{app="grocery-api", level="error"} | json | productId="PROD001"

# Inventory failures for any product
{app="grocery-api"} | json | event="inventory_check_failed"
```

---

## Key Events Reference

The Grocery API emits these structured events:

| Event | Level | Description | Key Fields |
|-------|-------|-------------|------------|
| `supplier_rate_limit_exceeded` | error | Supplier returned 429 | `productId`, `requestCount`, `limit`, `retryAfter`, `errorCode` |
| `inventory_check_failed` | error | Inventory lookup failed | `productId`, `reason`, `errorCode`, `retryAfter` |
| `inventory_check_success` | info | Inventory lookup succeeded | `productId`, `quantityAvailable` |
| `batch_inventory_rate_limited` | error | Batch hit rate limit | `productId`, `processedCount`, `remainingCount` |
| `batch_inventory_partial_failure` | error | Batch completed with errors | `summary.requested`, `summary.successful`, `summary.failed` |
| `supplier_rate_limit_reset` | info | Rate limit window reset | `previousCount` |
| `supplier_config` | info | Startup config logged | `rateLimit`, `resetWindowMs` |

---

## JSON Field Reference

| Field         | Type   | Description                                        |
|---------------|--------|----------------------------------------------------|
| `event`       | string | Event name (see table above)                       |
| `errorCode`   | string | Error identifier (e.g., `SUPPLIER_RATE_LIMIT_429`) |
| `message`     | string | Human-readable message                             |
| `productId`   | string | Product ID (e.g., `PROD001`)                       |
| `statusCode`  | number | HTTP status code                                   |
| `retryAfter`  | number | Seconds until rate limit resets                    |
| `requestCount`| number | Current request count in rate limit window         |
| `limit`       | number | Configured rate limit threshold                    |
| `supplier`    | string | Supplier name (e.g., `FreshFoods Wholesale API`)   |

---

## Formatted Output Queries

For quick human/agent-readable output:

```logql
# Compact error summary
{app="grocery-api", level="error"} | json | line_format "{{.event}}: {{.errorCode}} - {{.message}}"

# Rate limit details with timing
{app="grocery-api"} | json | errorCode="SUPPLIER_RATE_LIMIT_429" | line_format "[{{.productId}}] rate limit hit, retry in {{.retryAfter}}s (count={{.requestCount}}/{{.limit}})"

# Error timeline
{app="grocery-api", level="error"} | json | line_format "{{.time}} {{.event}} {{.errorCode}}"
```

---

## Correlation with Metrics

After identifying log patterns, correlate with Prometheus metrics (see [amw-queries.md](amw-queries.md)):

| Log Signal | Related Metric |
|------------|----------------|
| `SUPPLIER_RATE_LIMIT_429` events | `grocery_supplier_rate_limit_hits_total` |
| `inventory_check_failed` events | `grocery_supplier_requests_total{status="rate_limited"}` |
| Error rate in logs | `grocery_http_request_duration_seconds_count{status=~"5.."}` |

---

## Alert: SUPPLIER_RATE_LIMIT_429

An Azure Monitor Scheduled Query Rule exists:

- **Name**: `Grocery API - Supplier rate limit (SUPPLIER_RATE_LIMIT_429)`
- **Trigger**: KQL query on Container App console logs for `SUPPLIER_RATE_LIMIT_429`
- **Action**: Email notification via Action Group

If this alert fires, investigate using the queries in Section 1 above.
