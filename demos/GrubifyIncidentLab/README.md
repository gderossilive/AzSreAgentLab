# Grubify Incident Lab

Autonomous incident detection, diagnosis, and remediation with Azure SRE Agent — using a food ordering app (**Grubify**) with an intentional memory leak.

## Scenario

Grubify is a Node.js food ordering app deployed to Azure Container Apps. Its `/api/cart/{userId}/items` endpoint accumulates items in an in-memory cart with no eviction, causing unbounded memory growth under load.

When memory hits the 1 Gi container limit, the app OOMs or returns HTTP 500 errors. Azure Monitor fires an alert, and the **SRE Agent** autonomously investigates, diagnoses, and remediates.

## Three Personas

| Act | Persona | Subagent | GitHub? | What Happens |
|-----|---------|----------|---------|-------------|
| 1 | **IT Operations** | `incident-handler` (core) | No | Agent diagnoses memory leak via KQL log + metric analysis, restarts/scales container |
| 2 | **Developer** | `code-analyzer` | Yes | Agent correlates errors to cart API source code, files GitHub issue with file:line references |
| 3 | **Workflow Automation** | `issue-triager` | Yes | Agent classifies customer issue tickets, applies labels, posts triage comments |

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Resource Group (rg-{env})                              │
│                                                         │
│  ┌─────────────────────┐    ┌────────────────────────┐  │
│  │ Grubify Container   │───▶│ Log Analytics +        │  │
│  │ App (0.5 CPU, 1Gi)  │    │ Application Insights   │  │
│  └──────────┬──────────┘    └────────────────────────┘  │
│             │ HTTP 5xx                                   │
│  ┌──────────▼──────────┐    ┌────────────────────────┐  │
│  │ Azure Monitor Alert │───▶│ SRE Agent              │  │
│  │ (5xx > 5 in 5 min)  │    │ • incident-handler     │  │
│  └─────────────────────┘    │ • code-analyzer (GH)   │  │
│                              │ • issue-triager (GH)   │  │
│  ┌─────────────────────┐    │ • Knowledge Base (4 MD)│  │
│  │ Azure Container     │    └────────────────────────┘  │
│  │ Registry (ACR)      │                                │
│  └─────────────────────┘    ┌────────────────────────┐  │
│                              │ Managed Identity       │  │
│  ┌─────────────────────┐    │ (Reader, LAW, Mon,     │  │
│  │ GitHub MCP (opt.)   │    │  CA Contributor)       │  │
│  └─────────────────────┘    └────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

- Azure CLI (`az`) authenticated: `az login`
- Azure Developer CLI (`azd`) installed
- Azure subscription with access to `swedencentral`, `eastus2`, or `australiaeast`
- (Optional) GitHub PAT with `repo` scope — enables Developer + Workflow personas

## Quickstart

```bash
cd demos/GrubifyIncidentLab

# Clone Grubify source (needed for ACR build)
git clone https://github.com/dm-chelupati/grubify.git src/grubify

# Create azd environment
azd env new grubify-lab

# (Optional) Enable GitHub integration for Acts 2 & 3
azd env set GITHUB_PAT <your-github-pat>
azd env set GITHUB_USER <your-github-username>

# Deploy everything (Bicep infra + post-provision hook)
azd up
```

Deployment provisions: Resource Group, Log Analytics, App Insights, Container App Environment, Container App (Grubify), ACR, SRE Agent, Alert Rules, Managed Identity, RBAC assignments. The post-provision hook builds the Grubify container image in ACR and configures the agent (KB upload, subagents, response plan).

## Demo Execution

### Act 1: IT Operations — Autonomous Incident Response

```bash
# Trigger the memory leak
./scripts/break-app.sh

# Wait 5-8 minutes for:
#   1. Memory pressure to build in the container
#   2. Azure Monitor to fire the HTTP 5xx alert
#   3. SRE Agent to pick up and investigate the alert
#
# Watch at: https://sre.azure.com → Incidents
```

The agent will:
- Query container logs for error patterns (KQL)
- Check memory/CPU metrics
- Search the knowledge base for the HTTP 500 runbook
- Identify OOM / memory leak as root cause
- Remediate (restart or scale the container)
- Store findings in memory for future correlation

### Act 2: Developer — Code-Level Root Cause (requires GitHub)

After Act 1, the `code-analyzer` subagent can be triggered to:
- Search the GitHub repo for error patterns found in logs
- Pinpoint the `/api/cart/{userId}/items` handler — in-memory cart with no eviction
- Create a structured GitHub issue with file:line references and suggested fix

### Act 3: Workflow Automation — Issue Triage (requires GitHub)

```bash
# Seed sample customer issues
./scripts/create-sample-issues.sh <owner/repo>
```

The `issue-triager` runs on a 12-hour schedule and will:
- Read unprocessed `[Customer Issue]` titled issues
- Classify each (api-bug, memory-leak, feature-request, etc.)
- Apply labels and post triage comments

## Cleanup

```bash
cd demos/GrubifyIncidentLab
azd down --force --purge
```

## Re-running Without Full Redeploy

```bash
# Re-upload KB + recreate subagents (skip container build)
./scripts/post-provision.sh --skip-build

# Retry mode — skip build, re-upload KB only, skip response plan if it exists
./scripts/post-provision.sh --retry
```

## Key Files

| Path | Purpose |
|------|---------|
| [azure.yaml](azure.yaml) | azd template entry point |
| [infrastructure/main.bicep](infrastructure/main.bicep) | Subscription-scoped Bicep orchestrator |
| [infrastructure/resources.bicep](infrastructure/resources.bicep) | RG-scoped module composition |
| [scripts/post-provision.sh](scripts/post-provision.sh) | Post-provision: ACR build + KB upload + subagent creation |
| [scripts/break-app.sh](scripts/break-app.sh) | Fault injection (memory leak via cart API) |
| [scripts/create-sample-issues.sh](scripts/create-sample-issues.sh) | Seed GitHub issues for triage scenario |
| [sre-config/agents/](sre-config/agents/) | Subagent YAML specifications |
| [knowledge/](knowledge/) | Runbooks and reference docs uploaded to agent |
