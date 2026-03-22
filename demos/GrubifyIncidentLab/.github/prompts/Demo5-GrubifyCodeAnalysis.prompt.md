---
agent: agent
---

# Demo5-GrubifyCodeAnalysis

## Goal
Run **Act 2: Developer** — the `code-analyzer` subagent correlates production errors to source code, identifying the exact code path causing the memory leak, and files a structured GitHub issue with file:line references and a suggested fix.

## Prerequisites

### 1) GitHub integration is configured

```bash
cd /workspaces/AzSreAgentLab/demos/GrubifyIncidentLab
azd env get-value GITHUB_PAT 2>/dev/null | head -c 10 && echo "... (PAT set)"
```

If not set, configure it:
```bash
azd env set GITHUB_PAT <your-github-pat>
azd env set GITHUB_USER <your-github-username>
./scripts/post-provision.sh --skip-build
```

### 2) An incident exists from Act 1

Either run `./scripts/break-app.sh` again or reference the incident from Act 1. The `code-analyzer` subagent needs recent error patterns in the logs.

### 3) Verify code-analyzer subagent exists

```bash
AGENT_ENDPOINT=$(azd env get-value SRE_AGENT_ENDPOINT 2>/dev/null)
TOKEN=$(az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv)
curl -s "${AGENT_ENDPOINT}/api/v2/extendedAgent/agents/code-analyzer" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Name: {d[\"name\"]}, Tools: {len(d.get(\"properties\",{}).get(\"tools\",[]))+len(d.get(\"properties\",{}).get(\"mcpTools\",[]))}')"
```

## Execution

### Step 1: Trigger fault (if not already done in Act 1)

```bash
cd /workspaces/AzSreAgentLab/demos/GrubifyIncidentLab
./scripts/break-app.sh
```

### Step 2: Observe code-analyzer in action

Open https://sre.azure.com → **Incidents** and watch the code-analyzer subagent:

1. Query container logs for error patterns
2. Search the GitHub repository for matching code paths
3. Identify the cart API handler with unbounded in-memory accumulation
4. Create a GitHub issue with:
   - Incident summary and impact
   - Timeline of events
   - Evidence (log excerpts, metrics charts)
   - Root cause with file:line references
   - Suggested fix (add TTL/eviction to cart storage)

### Step 3: Review the GitHub issue

Check your GitHub repository for the newly created issue. It should follow the incident report template with structured sections.

## Success Criteria
- `code-analyzer` subagent correlates logs to source code
- A GitHub issue is created with file:line references to the cart API
- The issue includes a suggested code fix (memory eviction/TTL)
- Issue follows the incident report template format

## Constraints
- Requires `GITHUB_PAT` with `repo` scope
- The GitHub MCP connector must be active
