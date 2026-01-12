```prompt
---
agent: agent
---
You are helping a contributor **run** the ServiceNow Incident Automation demo after deployment is complete.

## Requirements
1) **Trigger the scenario (pick one) + generate traffic**
   Provide the simplest, script-driven options:
   - Option A (recommended): enable memory errors:
     - `./scripts/63-enable-memory-errors.sh`
   - Option B: enable CPU stress:
     - `./scripts/61-enable-cpu-stress.sh`
   - Generate traffic:
     - `./scripts/60-generate-traffic.sh`
   - Verify status / next actions:
     - `./scripts/61-check-memory.sh`

## Constraints
- Do not include or request secrets in outputs.
- Do not require Docker.

## Success Criteria
- A demo condition is enabled (memory errors or CPU stress).
- Traffic is generated.
- The operator can verify progress using `./scripts/61-check-memory.sh`.
