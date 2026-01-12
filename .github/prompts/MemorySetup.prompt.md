---
agent: agent
---
You are updating this repository’s “memory system”. Implement the following changes.

## Requirements
1) Create a `memory.md` file in the project root.
   - It must be a template for instance-specific working notes (deployment state, RG names, URLs, connector notes, known issues, next steps).
   - It must include a clear warning not to store secrets.

2) Add `memory.md` to the repo’s `.gitignore`.

3) Create/replace the current Copilot instructions with a compact “project constitution”.
   - The constitution must be committed (lives in `.github/copilot-instructions.md`).
   - It must explain the split:
     - Constitution = stable rules that always apply to this repo.
     - `memory.md` = instance-specific state that must not be committed.
   - Keep it short and actionable (no long how-to sections).

## Constraints
- Keep changes minimal and scoped to the requirements.
- Do not modify vendored sources under `external/`.
- Do not add new tooling or workflows.

## Success Criteria
- `memory.md` exists at repo root and is gitignored.
- `.github/copilot-instructions.md` is compact and clearly distinguishes constitution vs instance memory.
