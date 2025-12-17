# Lab helper scripts

Run these from the repo root:

```bash
source scripts/load-env.sh
scripts/10-clone-repos.sh
scripts/20-az-login.sh
scripts/30-deploy-octopets.sh  # provisions Octopets infrastructure via azd
scripts/31-deploy-octopets-containers.sh  # builds/deploys containers via ACR (no Docker)
scripts/40-deploy-sre-agent.sh  # deploys SRE Agent via Bicep
```
