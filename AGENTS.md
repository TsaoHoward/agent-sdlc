# AGENTS.md

## Purpose
This file defines how AI agents should work in this repository.

Agents must treat repository documents as durable project memory. Do not rely only on recent conversational context.

## Required Reading Order
Before planning or implementation, read these files in order:

1. `README.md`
2. `docs/project-overview.md`
3. `docs/operating-model.md`
4. `docs/environment-requirements.md`
5. `docs/architecture/overview.md`
6. `docs/architecture/task-lifecycle.md`
7. `docs/architecture/policy-representation.md`
8. `docs/architecture/runtime-isolation.md`
9. `docs/architecture/task-intake-contract.md`
10. `docs/architecture/agent-control-integration-plan.md`
11. `docs/architecture/pr-and-ci-path-definition.md`
12. `docs/architecture/lifecycle-traceability-contract.md`
13. `docs/roadmap.md`
14. `docs/wbs.md`
15. `docs/issues/*.md`
16. `docs/issues/items/*.md` referenced by active dashboard items
17. `docs/testing/README.md`
18. `docs/testing/test-plan.md`
19. `docs/testing/test-framework.md`
20. `docs/testing/test-dashboard.md`
21. `docs/testing/items/*.md` referenced by active dashboard items
22. `docs/decisions/*.md`
23. `docs/policies/*.md`

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
- `docs/issues/issue-dashboard.md` must follow `docs/templates/issue-dashboard.template.md`.
- supporting issue notes under `docs/issues/items/` should follow `docs/templates/issue-note.template.md` when created.
- `docs/decisions/decision-backlog.md` must follow `docs/templates/decision-backlog.template.md`.
- `docs/testing/test-dashboard.md` should follow `docs/templates/test-dashboard.template.md`.
- supporting test notes under `docs/testing/items/` should follow `docs/templates/test-case.template.md` when created.
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
- identify whether any active or newly discovered major issue item must be added or updated in `docs/issues/issue-dashboard.md`
- identify whether any active or newly discovered major test item must be added or updated in `docs/testing/test-dashboard.md`
- identify whether any open or newly discovered major decision item must be added or updated in `docs/decisions/decision-backlog.md`

During coding:
- avoid adding hidden coupling between layers
- avoid silently changing operating assumptions
- avoid placing durable policy only in prompt text
- avoid leaving meaningful major decision context only in chat when it affects future work

After coding:
- update WBS item status
- update roadmap if scope or milestone meaning changed
- update `docs/issues/issue-dashboard.md` when active issue items were discovered, split, reframed, blocked, completed, deferred, or closed
- move done, closed, or no-longer-near-term issue items out of the active issue dashboard when they no longer need dashboard visibility
- update or create supporting issue notes when dashboard summaries are no longer sufficient
- update `docs/testing/test-dashboard.md` when active test items were discovered, reframed, blocked, passed, failed, deferred, or retired
- move passed, retired, or no-longer-near-term test items out of the active test dashboard when they no longer need dashboard visibility
- update or create supporting test notes when dashboard summaries are no longer sufficient
- update `docs/decisions/decision-backlog.md` when major decisions were discovered, narrowed, selected, deferred, or promoted
- move ADR-promoted or closed items out of the active decision backlog when they no longer need dashboard visibility
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
