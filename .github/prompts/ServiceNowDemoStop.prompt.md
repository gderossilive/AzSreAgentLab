```prompt
---
agent: agent
---
You are helping a contributor **stop** the ServiceNow Incident Automation demo and return the lab to a normal state.

## Requirements
1) **Cleanup (return to normal)**
   - Disable the injected behaviors:
     - `./scripts/64-disable-memory-errors.sh`
     - `./scripts/62-disable-cpu-stress.sh`

## Constraints
- Do not include or request secrets in outputs.
- Do not require Docker.

## Success Criteria
- Any enabled demo behaviors are disabled (memory errors and/or CPU stress).
