# Loki Query Reference

Use this reference to query logs from applications in this environment.

## Apps in This Environment

| App Name | `app` label | `job` label | Description |
|----------|-------------|-------------|-------------|
| Grocery API | `grocery-api` | `grocery-api` | Product catalog, inventory & orders |

## Query Patterns

Replace `APP` with the `app` label value from the table above.

### Error Investigation

```logql
# All errors for an app
{app="APP", level="error"}

# Rate limit / 429 errors
{app="APP"} |= "429"

# Rate limit errors with details
{app="APP"} | json | errorCode=~".*RATE_LIMIT.*"

# Timeout errors
{app="APP", level="error"} |= "timeout"

# External service failures
{app="APP", level="error"} |= "failed"
```

### Error Counts & Trends

```logql
# Count errors over last hour
count_over_time({app="APP", level="error"}[1h])

# Error rate per 5 minutes
rate({app="APP", level="error"}[5m])

# Count rate limit events over time
count_over_time({app="APP"} |= "429" [1h])

# Errors grouped by errorCode
sum by (errorCode) (count_over_time({app="APP"} | json [1h]))
```

### Warnings (Early Signs of Issues)

```logql
# All warnings
{app="APP", level="warn"}

# Warnings and errors together
{app="APP", level=~"warn|error"}
```

### All Logs

```logql
# All logs for an app
{app="APP"}

# With formatted output
{app="APP"} | json | line_format "{{.level}}: {{.event}} - {{.message}}"
```

## Common Labels

| Label | Values |
|-------|--------|
| `app` | See Apps table above |
| `job` | Usually same as `app` |
| `level` | `info`, `warn`, `error` |
| `environment` | `production`, `development` |

## Common JSON Fields in Logs

| Field | Description |
|-------|-------------|
| `event` | Event type (e.g., `supplier_rate_limited`) |
| `errorCode` | Error code (e.g., `SUPPLIER_RATE_LIMIT`) |
| `message` | Human-readable description |
| `statusCode` | HTTP status code |
| `retryAfter` | Seconds until retry (for rate limits) |
| `duration` | Operation duration in ms |

## Issue Patterns

**Rate Limiting:**
- 429 status codes or `RATE_LIMIT` error codes
- Check `retryAfter` field for retry timing
- Use `count_over_time` to see frequency

**Service Degradation:**
- Errors with `statusCode` 500, 502, 503, 504
- High `duration` values
- Warnings appearing before errors

**Authentication Issues:**
- 401 or 403 status codes
- Messages with `auth`, `unauthorized`, `forbidden`
