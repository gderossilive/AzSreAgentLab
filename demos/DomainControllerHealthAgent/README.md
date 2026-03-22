# Domain Controller Health Agent

Scheduled Azure SRE Agent subagent that monitors Active Directory Domain Controllers for anomalies in authentication and DNS query activity.

## What It Does

The `domaincontrollerhealthagent` subagent runs on a schedule and compares current DC performance counters against the same window 7, 14, and 21 days ago (week-over-week). It fires a Teams alert only when a meaningful deviation is detected.

**Monitored metrics** (via Log Analytics → `Perf` table):
- `NTLM Authentications`
- `Kerberos Authentications`
- `Total Query Received/sec`

**Anomaly thresholds**:
| Severity | Delta from baseline |
|---|---|
| Medium | ≥ 20% |
| High | ≥ 30% |
| Critical | ≥ 50% |

## Contents

| Path | Purpose |
|---|---|
| `SubAgents/DomainControllerHealthAgent.yaml` | Subagent configuration YAML |

## Prerequisites

- Azure SRE Agent (Preview) deployed
- Domain Controllers sending Windows performance counters to a Log Analytics workspace
  - Counter names: `NTLM Authentications`, `Kerberos Authentications`, `Total Query Received/sec`
  - These are in the `Perf` table in Log Analytics
- (Optional) Microsoft Teams Power Automate webhook for alert delivery

## Setup

1. **Open Azure Portal** → navigate to your SRE Agent resource

2. **Go to "Subagent Builder"** → click "+ New Subagent"

3. **Configure the trigger**:
   - **Name**: `domaincontrollerhealthagent`
   - **Trigger type**: `Scheduled`
   - **Schedule**: `0 */6 * * *` (every 6 hours) or a frequency that suits your environment
   - **Mode**: `Autonomous`

4. **Paste the YAML** from `SubAgents/DomainControllerHealthAgent.yaml` into the editor

5. **Update the system prompt** if needed:
   - Optionally add a `Computer` filter to scope to your DC naming convention
     (see commented-out examples in the YAML)
   - Set the Log Analytics workspace scope

6. **Configure Teams connector** (optional but recommended):
   - Add a Teams connector in the SRE Agent portal → Connectors
   - The subagent will send anomaly alerts to Teams when deviations are found

7. **Click Validate → Save → Enable**

## KQL Reference

The subagent uses the following KQL pattern (simplified):

```kql
let anchor = now();
let FocusWindows = 15m;
let Frequency = 7d;
Perf
| where TimeGenerated between ((anchor-FocusWindows) .. (anchor))
    or TimeGenerated between ((anchor-1*Frequency-FocusWindows) .. (anchor-Frequency))
    or TimeGenerated between ((anchor-2*Frequency-FocusWindows) .. (anchor-2*Frequency))
    or TimeGenerated between ((anchor-3*Frequency-FocusWindows) .. (anchor-3*Frequency))
| where CounterName in ("NTLM Authentications", "Kerberos Authentications", "Total Query Received/sec")
// Optional: scope to DCs
// | where Computer startswith "DC"
| project TimeGenerated, CounterName, CounterValue, Computer
| summarize avgCounterValue=avg(CounterValue) by bin(TimeGenerated, 2*FocusWindows), CounterName, Computer
| sort by TimeGenerated desc
```

The subagent then computes `deltaPct = (current - baseline) / baseline * 100` and fires only when a configured threshold is exceeded.

## Expected Output

When a meaningful anomaly is found, the agent sends a Teams message summarising:
- Affected Domain Controller(s)
- Counter(s) that deviated
- Current value vs. baseline (avg of 7d/14d/21d windows)
- Computed delta percentage and severity

If no anomalies are detected, the subagent completes silently.
