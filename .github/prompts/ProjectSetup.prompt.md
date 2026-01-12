---
agent: agent
---
You are helping a new contributor set up and deploy this repository’s lab environment (Octopets + Azure SRE Agent). Produce a clear, copy/paste-friendly setup guide and make any minimal documentation fixes needed so the guide matches the actual scripts in `scripts/`.

## Requirements
1) **Prereqs section**
   - List the required tools:
     - Azure CLI (`az`)
     - Bash shell
     - Access to an Azure subscription
     - (Do **not** require local Docker; this repo uses ACR remote builds.)
   - List required Azure permissions:
     - Ability to run subscription-scope deployments (`az deployment sub create`) that create resource groups.
     - Ability to create role assignments (RBAC) at the SRE Agent RG scope and the Octopets RG scope.
     - Mention common working roles: `Owner`, or `Contributor` + `User Access Administrator` at the required scopes.
   - Specify the default/required region:
     - `swedencentral` (SRE Agent preview constraint).
   - Include security constraints:
     - Never commit `.env` or any secrets.
     - The SRE Agent must **not** get subscription-wide permissions; scope access to the target RG(s) only.

2) **Environment configuration**
   - Describe how to create `.env` from `.env.example`.
   - Call out the *minimum* variables required for the happy path:
     - `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_LOCATION`
     - `OCTOPETS_ENV_NAME`
     - `SRE_AGENT_RG_NAME`, `SRE_AGENT_NAME`, `SRE_AGENT_ACCESS_LEVEL`
   - Note that `OCTOPETS_RG_NAME` and `SRE_AGENT_TARGET_RESOURCE_GROUPS` are auto-populated by the Octopets infra deployment script.

3) **Setup + Deploy (happy path)**
   Provide the exact command sequence to deploy end-to-end from repo root:
   - `source scripts/load-env.sh`
   - `scripts/20-az-login.sh`
   - `scripts/30-deploy-octopets.sh`
   - `scripts/31-deploy-octopets-containers.sh`
   - `scripts/10-clone-repos.sh` (only if `external/sre-agent` is missing)
   - `scripts/40-deploy-sre-agent.sh`

   Include expected outputs/verification points:
   - `scripts/30-deploy-octopets.sh` sets `OCTOPETS_RG_NAME` and `SRE_AGENT_TARGET_RESOURCE_GROUPS` in `.env`.
   - `scripts/31-deploy-octopets-containers.sh` sets `OCTOPETS_API_URL` and `OCTOPETS_FE_URL` in `.env`.
   - The frontend URL should be reachable in a browser.

4) **Docs consistency (minimal fixes only)**
   - If any existing docs claim Octopets infra is deployed via `azd`, but the repo actually deploys via `az deployment sub create` + Bicep, update the docs to reflect reality.
   - Keep changes minimal and scoped to setup/deploy guidance.

## Constraints
- Do not modify vendored sources under `external/`.
- Do not add new tooling or workflows.
- Keep instructions aligned with the devcontainer assumptions (Linux, Azure CLI available).

## Success Criteria
- A new user can follow the guide and deploy the lab end-to-end using only the scripts in `scripts/`.
- `.env` is the only required local configuration file and remains uncommitted.
- The guide is consistent with the actual deployment scripts and respects the scoped-RBAC requirement.
