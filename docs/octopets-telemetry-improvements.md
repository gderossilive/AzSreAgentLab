# Octopets Application Insights Telemetry Improvements

## Overview

This document provides recommendations for improving Application Insights telemetry for the Octopets API to ensure better observability and incident investigation capabilities.

## Current Issue

Investigation of the High Response Time alert (fired 2026-01-27T01:28:00Z) revealed sparse telemetry:
- Only 2 request events in App Insights for the 01:00-02:00Z hour
- Zero dependency tracking
- No detailed telemetry for the slow 4xx responses that triggered the alert

## Recommended Improvements

### 1. Application Insights SDK Integration

The Octopets API should integrate the Application Insights SDK to ensure comprehensive telemetry collection.

**For .NET Applications** (ASP.NET Core):

Add to `Program.cs` or startup configuration:

```csharp
// Add Application Insights telemetry
builder.Services.AddApplicationInsightsTelemetry();

// Configure sampling (adjust percentage as needed for your environment)
builder.Services.Configure<TelemetryConfiguration>(config =>
{
    config.DefaultTelemetrySink.TelemetryProcessorChainBuilder
        .Use(next => new AdaptiveSamplingTelemetryProcessor(next)
        {
            MaxTelemetryItemsPerSecond = 5,
            SamplingPercentageDecreaseTimeout = TimeSpan.FromSeconds(2),
            SamplingPercentageIncreaseTimeout = TimeSpan.FromMinutes(15),
            InitialSamplingPercentage = 100
        })
        .Build();
});
```

### 2. Connection String Configuration

Ensure the Application Insights connection string is configured via environment variables:

```bash
# In Container App environment variables
APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=<key>;IngestionEndpoint=<endpoint>"
```

The connection string can be retrieved from the Application Insights resource. The deployment script (`scripts/31-deploy-octopets-containers.sh`) should be updated to include this environment variable.

### 3. Dependency Tracking

Enable automatic dependency tracking for:
- HTTP calls to downstream services
- Database queries
- External API calls

```csharp
// Dependency tracking is automatic with Application Insights SDK
// Ensure HttpClient is registered through dependency injection
builder.Services.AddHttpClient();
```

### 4. Custom Telemetry for 4xx Responses

Add custom tracking for validation failures and client errors to understand slow 4xx responses:

```csharp
app.Use(async (context, next) =>
{
    var sw = Stopwatch.StartNew();
    await next();
    sw.Stop();
    
    if (context.Response.StatusCode >= 400 && context.Response.StatusCode < 500)
    {
        var telemetryClient = context.RequestServices.GetRequiredService<TelemetryClient>();
        telemetryClient.TrackEvent("Slow4xxResponse", new Dictionary<string, string>
        {
            { "Path", context.Request.Path },
            { "StatusCode", context.Response.StatusCode.ToString() },
            { "DurationMs", sw.ElapsedMilliseconds.ToString() }
        });
    }
});
```

### 5. Cloud Role Name Configuration

Ensure consistent cloud_RoleName for filtering telemetry:

```csharp
builder.Services.AddSingleton<ITelemetryInitializer>(provider =>
{
    return new CloudRoleNameInitializer("octopetsapi");
});

public class CloudRoleNameInitializer : ITelemetryInitializer
{
    private readonly string _roleName;
    
    public CloudRoleNameInitializer(string roleName)
    {
        _roleName = roleName;
    }
    
    public void Initialize(ITelemetry telemetry)
    {
        telemetry.Context.Cloud.RoleName = _roleName;
    }
}
```

### 6. Sampling Configuration

For production environments, configure appropriate sampling to balance cost and visibility:

- **Low traffic environments**: 100% sampling
- **Medium traffic**: 20-50% sampling
- **High traffic**: 5-20% sampling with adaptive sampling

**Important**: Always use 100% sampling for critical errors (5xx responses).

## Implementation Steps

Since the Octopets source code is in the `external/octopets` directory (read-only vendored content), these changes should be:

1. **Proposed to the upstream Octopets repository** (if it's a shared sample)
2. **Applied to a local fork** of the Octopets code if customization is needed
3. **Configured via Container App environment variables** where possible

## Container App Configuration Updates

Update `scripts/31-deploy-octopets-containers.sh` to include Application Insights configuration:

```bash
# Retrieve Application Insights connection string
app_insights_name="$(az monitor app-insights component list -g "$OCTOPETS_RG_NAME" --query "[0].name" -o tsv)"
app_insights_conn_string="$(az monitor app-insights component show -g "$OCTOPETS_RG_NAME" -a "$app_insights_name" --query "connectionString" -o tsv)"

# Add to container app environment variables
az containerapp update -g "$OCTOPETS_RG_NAME" -n "$api_app" \
  --set-env-vars \
    "EnableSwagger=true" \
    "ASPNETCORE_URLS=http://+:8080" \
    "APPLICATIONINSIGHTS_CONNECTION_STRING=$app_insights_conn_string"
```

## Validation

After implementing these changes, validate telemetry using:

```kusto
// Check requests are being ingested
requests
| where timestamp > ago(1h)
| where cloud_RoleName == "octopetsapi"
| summarize count() by bin(timestamp, 1m), resultCode
| order by timestamp desc

// Check dependency tracking
dependencies
| where timestamp > ago(1h)
| where cloud_RoleName == "octopetsapi"
| summarize count() by name, target
| order by count_ desc

// Check 4xx response times
requests
| where timestamp > ago(1h)
| where cloud_RoleName == "octopetsapi"
| where resultCode startswith "4"
| summarize avg(duration), percentile(duration, 95), percentile(duration, 99) by resultCode
```

## Expected Outcomes

After implementing these improvements:

1. ✅ Consistent telemetry ingestion (no gaps in request data)
2. ✅ Full dependency tracking for downstream calls
3. ✅ Detailed metrics for 4xx responses including execution paths
4. ✅ Ability to correlate slow responses with specific endpoints/operations
5. ✅ Better incident investigation with complete telemetry trail

## Related Files

- Alert configuration: `demos/AzureHealthCheck/octopets-az-monitor-alerts.bicep`
- Deployment script: `scripts/31-deploy-octopets-containers.sh`
- Container dockerfile: `docker/octopetsapi-otel/Dockerfile` (uses OpenTelemetry auto-instrumentation)

## Alternative: OpenTelemetry Approach

The `docker/octopetsapi-otel/Dockerfile` already includes OpenTelemetry auto-instrumentation. To use this approach:

1. Build and deploy using the `docker/octopetsapi-otel/Dockerfile`
2. Configure the OpenTelemetry Collector to export to Application Insights
3. Set appropriate environment variables for OTLP endpoint and service name

See `docker/otelcol-ai/` for the collector configuration example.
