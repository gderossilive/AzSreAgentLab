# AMW / Prometheus Query Reference

Use this reference to query **Prometheus metrics** stored in the **Azure Monitor Workspace (Managed Prometheus)** for this environment.

You can run these queries in:

- **Azure Managed Grafana** → *Explore* → select the Prometheus datasource (typically **Prometheus (AMW)**)
- MCP tool `amgmcp_query_datasource` (datasourceName **Prometheus (AMW)**) with a time window (`fromMs`/`toMs`)

## Apps / Jobs in This Environment

| Component | `job` label | What it represents |
|----------|-------------|--------------------|
| Grocery API | `ca-api` | Metrics scraped from the Grocery API Container App |
| HTTP probe | `blackbox-http` | Blackbox exporter probe metrics for HTTP endpoint health |

Tip: start with `up{job="…"}` to confirm series exist.

## Quick Sanity Checks

```promql
# Are targets being scraped?
up

# Is the Grocery API target up?
up{job="ca-api"}

# Is the HTTP probe succeeding?
probe_success{job="blackbox-http"}
```

## Availability & Error Signals

```promql
# % availability (assuming probe_success=1 on success)
100 * avg_over_time(probe_success{job="blackbox-http"}[5m])

# Detect scrape gaps (missing data is often the first clue)
absent_over_time(up{job="ca-api"}[5m])

# Container restarts (if kube-state-metrics is present)
increase(kube_pod_container_status_restarts_total[15m])
```

## HTTP Traffic & Errors

In this demo, the API exports HTTP server metrics with a `grocery_` prefix.

```promql
# Requests/sec (overall)
sum(rate(grocery_http_request_duration_seconds_count{job="ca-api"}[5m]))

# Requests/sec by status
sum by (status) (rate(grocery_http_request_duration_seconds_count{job="ca-api"}[5m]))

# 5xx error rate
sum(rate(grocery_http_request_duration_seconds_count{job="ca-api", status=~"5.."}[5m]))

# Error ratio
(
  sum(rate(grocery_http_request_duration_seconds_count{job="ca-api", status=~"5.."}[5m]))
)
/
(
  sum(rate(grocery_http_request_duration_seconds_count{job="ca-api"}[5m]))
)
```

If you have different instrumentation enabled, you may also see other common HTTP metric name patterns (for example `http_requests_total` or `http_server_request_duration_seconds_count`).

## Latency (p50/p95/p99)

The demo exports a request duration histogram (`grocery_http_request_duration_seconds_bucket`).

```promql
# p95 latency
histogram_quantile(
  0.95,
  sum by (le) (rate(grocery_http_request_duration_seconds_bucket{job="ca-api"}[5m]))
)

# p99 latency
histogram_quantile(
  0.99,
  sum by (le) (rate(grocery_http_request_duration_seconds_bucket{job="ca-api"}[5m]))
)
```

## Container / Platform Metrics (Kubernetes)

If you enabled Container Apps → Managed Prometheus scraping, you may have some kube / cAdvisor metrics available.

```promql
# CPU usage (cores) by pod (if container_cpu_usage_seconds_total is present)
sum by (pod) (rate(container_cpu_usage_seconds_total[5m]))

# Memory working set by pod
sum by (pod) (container_memory_working_set_bytes)

# Throttling (if present)
sum(rate(container_cpu_cfs_throttled_seconds_total[5m]))
```

## Useful Patterns

```promql
# Top-N by rate (example: busiest endpoints if route labels exist)
topk(10, sum by (route) (rate(grocery_http_request_duration_seconds_count{job="ca-api"}[5m])))

# Compare two time windows (current vs 1h ago)
(
  sum(rate(grocery_http_request_duration_seconds_count{job="ca-api"}[5m]))
)
-
(
  sum(rate(grocery_http_request_duration_seconds_count{job="ca-api"}[5m] offset 1h))
)
```

## Troubleshooting Checklist

- **No data returned**: confirm the datasource is correct and `up{job="ca-api"}` returns series.
- **403 from AMW direct queries**: the calling identity needs **Monitoring Data Reader** on the Azure Monitor Workspace.
- **Gaps / flapping**: check `absent_over_time(up{job="ca-api"}[5m])` and compare with deployment/revision events.
- **Metric name mismatch**: use Grafana Explore’s metric browser to find the actual metric names and labels, then adapt queries above.
