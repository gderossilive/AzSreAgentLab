# Prometheus / AMW Query Reference — Grocery API (SRE Agent)

This is an **SRE Agent knowledge file** providing PromQL queries for diagnosing Grocery API issues via Azure Monitor Workspace (Managed Prometheus).

---

## TL;DR for Agents

| Symptom                           | First Query |
|-----------------------------------|-------------|
| Is the API running?               | `up{job="ca-api"}` |
| High error rate (5xx)             | `sum(rate(grocery_http_request_duration_seconds_count{job="ca-api",status=~"5.."}[5m]))` |
| Supplier rate limit hits          | `sum(rate(grocery_supplier_rate_limit_hits_total[5m]))` |
| Request throughput                | `sum(rate(grocery_http_request_duration_seconds_count{job="ca-api"}[5m]))` |
| P95 latency                       | `histogram_quantile(0.95, sum by (le) (rate(grocery_http_request_duration_seconds_bucket{job="ca-api"}[5m])))` |

---

## Quick Facts

- **Jobs**: `ca-api` (Grocery API), `blackbox-http` (blackbox exporter)
- **Metric prefix**: `grocery_` (custom app metrics)
- **Datasource**: `Prometheus (AMW)` in Grafana
- **Rate limit window**: 60 seconds (default `RATE_LIMIT_RESET_MS`)

---

## Symptom → Query Decision Tree

### 1. Is the API healthy?

```promql
# API is running (1 = up, 0 = down)
up{job="ca-api"}

# Blackbox HTTP probe result
probe_success{job="blackbox-http"}

# Blackbox probe duration
probe_duration_seconds{job="blackbox-http"}
```

### 2. HTTP traffic overview (RED method)

**Rate** (requests/sec):
```promql
# Total RPS
sum(rate(grocery_http_request_duration_seconds_count{job="ca-api"}[5m]))

# RPS by HTTP status
sum by (status) (rate(grocery_http_request_duration_seconds_count{job="ca-api"}[5m]))

# RPS by route
sum by (route) (rate(grocery_http_request_duration_seconds_count{job="ca-api"}[5m]))
```

**Errors** (5xx rate):
```promql
# 5xx errors/sec
sum(rate(grocery_http_request_duration_seconds_count{job="ca-api",status=~"5.."}[5m]))

# 5xx error percentage
(
  sum(rate(grocery_http_request_duration_seconds_count{job="ca-api",status=~"5.."}[5m]))
  /
  sum(rate(grocery_http_request_duration_seconds_count{job="ca-api"}[5m]))
) * 100
```

**Duration** (latency):
```promql
# P50 latency
histogram_quantile(0.50, sum by (le) (rate(grocery_http_request_duration_seconds_bucket{job="ca-api"}[5m])))

# P95 latency
histogram_quantile(0.95, sum by (le) (rate(grocery_http_request_duration_seconds_bucket{job="ca-api"}[5m])))

# P99 latency
histogram_quantile(0.99, sum by (le) (rate(grocery_http_request_duration_seconds_bucket{job="ca-api"}[5m])))

# Latency by route
histogram_quantile(0.95, sum by (le, route) (rate(grocery_http_request_duration_seconds_bucket{job="ca-api"}[5m])))
```

### 3. Supplier rate limiting (root cause for 503s)

```promql
# Rate limit hits/sec (key indicator!)
sum(rate(grocery_supplier_rate_limit_hits_total[5m]))

# Total rate limit hits (counter)
grocery_supplier_rate_limit_hits_total

# Supplier requests by status (success vs rate_limited)
sum by (status) (rate(grocery_supplier_requests_total[5m]))

# Current request count in rate limit window
grocery_supplier_request_count
```

### 4. Resource utilization

```promql
# CPU usage (cores)
sum(rate(grocery_process_cpu_seconds_total{job="ca-api"}[5m]))

# Memory usage (bytes)
grocery_process_resident_memory_bytes{job="ca-api"}

# Open file descriptors
grocery_process_open_fds{job="ca-api"}
```

---

## Key Metrics Reference

| Metric | Type | Description |
|--------|------|-------------|
| `grocery_http_request_duration_seconds_count` | Counter | HTTP request count (by method, route, status) |
| `grocery_http_request_duration_seconds_bucket` | Histogram | HTTP latency buckets |
| `grocery_supplier_requests_total` | Counter | Supplier API calls (by status: success/rate_limited) |
| `grocery_supplier_rate_limit_hits_total` | Counter | Supplier 429 responses received |
| `grocery_supplier_request_count` | Gauge | Current requests in rate limit window |
| `grocery_process_cpu_seconds_total` | Counter | CPU time consumed |
| `grocery_process_resident_memory_bytes` | Gauge | Memory usage |
| `up` | Gauge | Target health (1 = up) |
| `probe_success` | Gauge | Blackbox probe result (1 = success) |

---

## Alerting Thresholds (Guidance)

| Condition | Suggested Threshold | Severity |
|-----------|---------------------|----------|
| API down | `up{job="ca-api"} == 0` for 2m | Critical |
| High 5xx rate | `5xx_percentage > 5%` for 5m | Warning |
| High 5xx rate | `5xx_percentage > 20%` for 5m | Critical |
| Supplier rate limit | `rate(grocery_supplier_rate_limit_hits_total[5m]) > 0` | Warning |
| P95 latency | `> 2s` for 5m | Warning |

---

## Correlation with Logs

Use these metrics alongside Loki queries (see [loki-queries.md](loki-queries.md)):

| Metric Signal | Correlated Log Query |
|---------------|----------------------|
| `grocery_supplier_rate_limit_hits_total` increasing | `{app="grocery-api"} \| json \| errorCode="SUPPLIER_RATE_LIMIT_429"` |
| `status=~"5.."` requests increasing | `{app="grocery-api", level="error"}` |
| Inventory route errors | `{app="grocery-api"} \| json \| event="inventory_check_failed"` |

---

## Dashboard Panels

The Grocery SRE Overview dashboard (UID: `afbppudwbhl34b`) includes these Prometheus panels:

| Panel Title | Query | Type |
|-------------|-------|------|
| Requests/sec (API) | `sum(rate(grocery_http_request_duration_seconds_count{job="ca-api"}[5m]))` | timeseries |
| CPU usage (cores) | `sum(rate(grocery_process_cpu_seconds_total{job="ca-api"}[5m]))` | stat |

To retrieve panel data programmatically:
```
amgmcp_get_panel_data(panelTitle="Requests/sec (API)")
amgmcp_get_panel_data(panelTitle="CPU usage (cores)")
```

---

## Troubleshooting Checklist

1. **Verify connectivity**: `up{job="ca-api"}` should return `1`
2. **Check request volume**: `sum(rate(grocery_http_request_duration_seconds_count{job="ca-api"}[5m]))` > 0
3. **Look for errors**: `sum(rate(...{status=~"5.."}[5m]))` — any 5xx?
4. **Check supplier status**: `rate(grocery_supplier_rate_limit_hits_total[5m])` — hitting limits?
5. **Correlate with logs**: Use LogQL queries from [loki-queries.md](loki-queries.md)
