# Copilot Instructions — AzSreAgentLab

## Project Constitution (committed)
This file is the **stable, repo-wide constitution**: rules that always apply.

- Purpose: lab repo to deploy Octopets + Azure SRE Agent (Preview) and run demos (ServiceNow incident automation, scheduled health checks).
- Environment: VS Code devcontainer on Linux; assume **no local Docker daemon**.
- Builds: use ACR remote builds (`az acr build`) with repo root as build context.
- IaC: prefer Bicep; use correct scope (`az deployment sub` vs `az deployment group`).
- Region: use `swedencentral` by default (SRE Agent preview region constraint).
- Security: least privilege; never grant subscription-wide permissions to the agent—scope RBAC to the target resource group(s).
- Secrets: never commit `.env` or any secret material.
- Vendored sources: `external/` is reference content; treat as read-only unless explicitly asked.

## Instance Memory (not committed)
Use [memory.md](../memory.md) for **instance-specific working state** (deployment names, RGs, URLs, connector notes, known issues, next steps).

- [memory.md](../memory.md) is gitignored and must not contain secrets.
- Before doing work: read [memory.md](../memory.md) if present.
- After making decisions/deployments: update [memory.md](../memory.md).
