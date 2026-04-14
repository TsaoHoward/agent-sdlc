# AGENTS.md

## Purpose
This file defines how AI agents should work in this repository.

Agents must treat repository documents as durable project memory. Do not rely only on recent conversational context.

## Required Reading Order
Before planning or implementation, read these files in order:

1. `README.md`
2. `docs/project-overview.md`
3. `docs/operating-model.md`
4. `docs/architecture/overview.md`
5. `docs/architecture/task-lifecycle.md`
6. `docs/architecture/policy-representation.md`
7. `docs/architecture/runtime-isolation.md`
8. `docs/roadmap.md`
9. `docs/wbs.md`
10. `docs/decisions/*.md`
11. `docs/policies/*.md`

## Core Working Rules
1. Plan before implementation.
2. Check roadmap and WBS before large changes.
3. Keep architecture boundaries intact unless an ADR explicitly changes them.
4. Do not turn a tool choice into a hidden architecture decision.
5. Keep workflow, policy, and governance logic externalized whenever practical.
6. Treat CI as an independent verifier, not as part of the agent itself.
7. Treat deployment as separate from agent execution.

## Planning Rules
- `docs/roadmap.md` must follow `docs/templates/roadmap.template.md`.
- `docs/wbs.md` must follow `docs/templates/wbs.template.md`.
- If the template structure is no longer sufficient, update the relevant template first, then update the generated document.
- All major implementation work should be traceable to a roadmap phase and one or more WBS items.

## Change Control Rules
Create or update an ADR before implementation if the change affects:
- system boundaries
- source-of-truth ownership
- task/event routing model
- security or execution isolation model
- CI ownership or verification model
- deployment responsibility
- cross-cutting policy or governance rules

## Drift Prevention Rules
Before coding:
- identify the relevant roadmap phase
- identify the relevant WBS item(s)
- confirm whether an ADR is required
- confirm whether the change belongs to architecture, policy, or implementation

During coding:
- avoid adding hidden coupling between layers
- avoid silently changing operating assumptions
- avoid placing durable policy only in prompt text

After coding:
- update WBS item status
- update roadmap if scope or milestone meaning changed
- update architecture docs if boundaries changed
- update or create ADRs for architecture-level shifts
- update policies if intake/approval/ownership rules changed

## Implementation Constraints for Early Phases
During initialization and early phases:
- prefer documentation, structure, and minimal scaffolding
- do not implement broad business functionality prematurely
- preserve replaceability for forge, agent runtime, CI, and deploy layers

## Expected Output Style
When producing plans or proposals:
- be concrete
- mark assumptions clearly
- separate goals from non-goals
- separate decisions from open questions
- separate architecture boundaries from implementation details

## If the Repo State Is Inconsistent
If documents conflict:
1. identify the conflict explicitly
2. treat ADRs as the decision history
3. propose a resolution
4. do not silently merge conflicting assumptions
