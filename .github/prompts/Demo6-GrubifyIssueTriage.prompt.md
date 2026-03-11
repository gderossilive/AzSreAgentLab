---
agent: agent
---

# Demo6-GrubifyIssueTriage

## Goal
Run **Act 3: Workflow Automation** — seed sample customer issues in a GitHub repo and let the `issue-triager` subagent classify, label, and comment on each one.

## Prerequisites

### 1) GitHub integration is configured

```bash
cd /workspaces/AzSreAgentLab/demos/GrubifyIncidentLab
azd env get-value GITHUB_PAT 2>/dev/null | head -c 10 && echo "... (PAT set)"
azd env get-value GITHUB_USER 2>/dev/null
```

### 2) Verify issue-triager subagent exists

```bash
AGENT_ENDPOINT=$(azd env get-value SRE_AGENT_ENDPOINT 2>/dev/null)
TOKEN=$(az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv)
curl -s "${AGENT_ENDPOINT}/api/v2/extendedAgent/agents/issue-triager" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Name: {d[\"name\"]}')"
```

## Execution

### Step 1: Create sample customer issues

```bash
cd /workspaces/AzSreAgentLab/demos/GrubifyIncidentLab

# Set the target repo (owner/repo format)
export GITHUB_PAT=$(azd env get-value GITHUB_PAT 2>/dev/null)
./scripts/create-sample-issues.sh <owner/repo>
```

This creates 5 realistic customer-reported issues with `[Customer Issue]` in the title:
- App crashes when adding items to cart (api-bug / memory-leak)
- Menu page loading slowly (performance)
- Can't place an order — 500 error (api-bug)
- Feature request — add restaurant search (feature-request)
- How do I clear my cart? (question)

### Step 2: Trigger the issue-triager

The `issue-triager` runs on a scheduled task (every 12 hours via cron). To verify it's set up:

```bash
AGENT_ENDPOINT=$(azd env get-value SRE_AGENT_ENDPOINT 2>/dev/null)
TOKEN=$(az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv)
curl -s "${AGENT_ENDPOINT}/api/v1/scheduledtasks" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -c "
import sys,json
for t in json.load(sys.stdin):
    print(f'{t[\"name\"]} ({t[\"cronExpression\"]}) → {t.get(\"agent\",\"(none)\")} [{t.get(\"status\",\"?\")}]')
"
```

You can also manually trigger the triager from the SRE Agent portal at https://sre.azure.com.

### Step 3: Review triaged issues

After the triager runs, check your GitHub issues. Each `[Customer Issue]` should have:
- Classification labels applied (e.g., `api-bug`, `memory-leak`, `feature-request`, `question`)
- A triage comment with analysis, classification rationale, and next steps

## Success Criteria
- 5 sample issues created successfully in the GitHub repo
- Scheduled task `triage-grubify-issues` is active
- After triage runs: issues have labels applied and triage comments posted
- Classifications are reasonable (cart crash → api-bug/memory-leak, search request → feature-request, etc.)

## Constraints
- Requires `GITHUB_PAT` with `repo` scope
- The GitHub MCP connector must be active
- Issue titles must contain `[Customer Issue]` to be picked up by the triager
