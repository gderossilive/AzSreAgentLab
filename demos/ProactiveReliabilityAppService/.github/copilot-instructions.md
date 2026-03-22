# Copilot Instructions — ProactiveReliabilityAppService

## Project Constitution (committed)
This file is the **stable, repo-wide constitution**: rules that always apply.

- Purpose: Proactive reliability demo — Azure App Service slot swap triggers a regression, and the Azure SRE Agent autonomously detects and remediates it.
- Environment: VS Code devcontainer on Linux; assume **no local Docker daemon**.
- Builds: use ACR remote builds (`az acr build`) with repo root as build context.
- IaC: prefer Bicep; use correct scope (`az deployment sub` vs `az deployment group`).
- Region: use `swedencentral` by default (SRE Agent preview region constraint).
- Security: least privilege; never grant subscription-wide permissions to the agent—scope RBAC to the target resource group(s).
- Secrets: never commit `.env` or any secret material.
- Vendored sources: `external/` is reference content; treat as read-only unless explicitly asked.

## Doc hygiene (committed)

- When updating docs that describe MCP tool surfaces, derive the list from the actual server implementation (e.g., search for `@mcp.tool()` in the relevant file) instead of copying from memory.

## Instance Memory (not committed)
Use `memory.md` for **instance-specific working state** (deployment names, RGs, URLs, connector notes, known issues, next steps).

- `memory.md` is gitignored and must not contain secrets.
- Before doing work: read `memory.md` if present.
- After making decisions/deployments: update `memory.md`.
