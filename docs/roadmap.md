# Roadmap

## Document Metadata
- Version: 0.1
- Status: Draft
- Last Updated: 2026-04-15
- Owner: Project Maintainer
- Source Template: docs/templates/roadmap.template.md

## Planning Principles
- This roadmap must align with `docs/project-overview.md`.
- This roadmap must be consistent with `docs/architecture/overview.md`.
- Each phase should map to one or more WBS sections in `docs/wbs.md`.
- Assumptions and open questions must remain explicit.

## Environment Requirements First
This roadmap follows the environment capability requirements defined in `docs/environment-requirements.md`.
Phase planning is sequenced from those requirements: define the environment baseline first, then schedule Phase 0 and Phase 1 against that baseline.

## Scope Summary
### Goals
- Establish a maintainable baseline for an agent-oriented SDLC system.
- Deliver a minimum closed loop from task intake to verified PR proposal.
- Preserve replaceability across forge, agent, runtime, CI, and deploy concerns.

### Non-Goals
- Full production platform in the first delivery.
- Full multi-agent orchestration in phase 1.
- Direct production deployment by the agent runtime.

### Current Assumptions
- The first forge target for Phase 1 is Gitea.
- The first policy representation uses docs plus machine-readable repository config.
- The early execution runtime uses isolated ephemeral containers.
- The first trigger path is a Gitea issue comment command.
- The first issue comment contract uses short task tokens plus a bounded `summary:` field with fail-closed parsing.
- The first machine-readable policy layout is split by policy unit.
- The first agent control integration uses a direct session starter interface.
- The first PR path creates the branch and PR immediately.
- The first traceability display uses a PR body summary plus linked metadata artifact.
- The first traceability and session records use file-backed JSON records under `.agent-sdlc/`.
- The platform's core control-plane implementation converges toward `TypeScript` on `Node.js LTS` with `npm` as the package surface.
- Repo-owned Dockerfiles should define the control-plane and worker packaging baseline before the project consolidates into a repo-owned `docker compose` package.
- CI remains independent and outside the agent control plane.
- Human review remains a required merge control point.

### Key Constraints
- Avoid premature lock-in to a single tool.
- Keep planning documents stable enough for future agent runs.
- Separate architecture, policy, planning, and implementation concerns.

## Environment Requirements First
This roadmap is grounded on the environment capability requirements defined in `docs/environment-requirements.md`.
Phase planning should follow those requirements: define what the environment must provide first, then schedule phases against that baseline.

---

## Phase 0 — Initialization / Baseline
### Objective
Create durable planning, architecture, and operating documents that can guide future agent and human work.

### Scope
- repository baseline
- architecture boundaries
- roadmap/WBS format
- initial ADRs and policy docs
- issue dashboard, archive, and supporting-note workflow
- early execution profiles and traceability conventions
- initialization prompt(s)

### Deliverables
- README
- AGENTS.md
- project overview
- environment requirements baseline
- architecture overview, context, and task lifecycle docs
- roadmap and WBS
- initial ADRs
- issue dashboard, issue archive, and issue-note template
- intake and change-control policies
- issue-management policy
- documented execution profiles and lifecycle traceability guidance
- initialization prompt

### Entry Criteria
- repository exists
- project direction is clear enough to define target experience and boundaries

### Exit Criteria
- durable documentation baseline exists
- roadmap and WBS are internally consistent
- architecture boundaries are documented
- shared environment requirements are tracked in one durable document
- minimum execution profiles and lifecycle identifiers are documented in durable repo docs
- active near-term project issues can be tracked durably with explicit exit paths and supporting notes when needed
- future agents can bootstrap from repository docs instead of conversation memory alone

### Dependencies
- agreement on high-level experience target
- agreement on layered architecture principle

### Risks
- over-specifying too early
- leaving documents too abstract to guide actual implementation
- failing to separate stable doctrine from editable planning artifacts

### Notes
This phase intentionally prioritizes structure over deep implementation.

---

## Phase 1 — Minimum Closed Loop
### Objective
Implement the smallest working path from task trigger to independently verified change proposal.

### Scope
- one trigger path
- one normalized task request path
- one traceability contract across lifecycle handoffs
- one agent control integration
- one isolated execution runtime
- one PR creation flow
- one CI verification flow
- one human review point

### Deliverables
- task intake adapter
- normalized task request model with stable identifiers and policy references
- agent session starter
- isolated worker runtime scaffold
- branch/PR proposal path
- CI workflow skeleton
- traceable task lifecycle contract and minimal logging

### Entry Criteria
- Phase 0 baseline completed
- chosen first forge, policy, and runtime assumptions documented
- ADRs written for first implementation target if needed

### Exit Criteria
- a supported task trigger can produce a bounded agent-run change proposal
- CI validates the proposed change independently
- human review remains the merge gate

### Dependencies
- task model definition
- execution-profile policy definition
- traceability contract
- runtime isolation model
- environment requirements baseline
- forge integration target documentation
- CI integration target

### Risks
- hidden coupling between intake and agent runtime
- weak task normalization
- policy or traceability logic being buried in prompts or code
- CI treated as an afterthought instead of an independent boundary

### Notes
Keep the first closed loop narrow. Solve one path well before broad expansion.

---

## Phase 2 — Controlled Expansion
### Objective
Add breadth without collapsing system boundaries.

### Scope
- more task sources
- richer policy packs
- improved observability
- stronger repository conventions
- better error handling and retry behavior
- initial governance tooling

### Deliverables
- more adapters
- richer policy/context definition
- lifecycle visibility and audit trail improvements
- reusable task templates
- failure classification and handling rules

### Entry Criteria
- Phase 1 closed loop is stable enough to demonstrate repeated use
- key interfaces have held up through initial implementation

### Exit Criteria
- system supports more than one intake pattern or more than one supported work profile
- governance and failure handling are explicit
- replaceability assumptions remain intact

### Dependencies
- stable task request contract
- stable agent/runtime handoff contract
- logging and audit strategy

### Risks
- scaling ad hoc rules faster than architecture
- expanding without strengthening policy boundaries
- accidental platform coupling

### Notes
Expansion should be driven by clear value, not by feature accumulation.

---

## Phase 3 — Multi-source / Governance Evolution
### Objective
Evolve from a narrow closed loop into a platform with better governance, source diversity, and longer-term replaceability.

### Scope
- additional source systems
- broader orchestration policies
- stronger governance and audit structures
- optional multi-agent or multi-profile support
- stronger release handoff patterns

### Deliverables
- adapter abstraction maturity
- governance model refinement
- more formal policy store or policy representation
- stronger approval and escalation patterns
- broader lifecycle reporting

### Entry Criteria
- earlier phases proved useful in practice
- major interface boundaries are stable enough to extend

### Exit Criteria
- the system can grow beyond a single path without losing control of architecture
- governance is explicit and maintainable
- component replacement paths are clearer and better tested

### Dependencies
- interface stability
- policy model maturity
- maintainable audit and review approach

### Risks
- governance sprawl
- abstraction drift
- replacing clarity with complexity

### Notes
This phase should only proceed when prior boundaries are understood and defended.

---

## Milestone Mapping
| Milestone ID | Name | Related Phase | Output | Validation |
|---|---|---|---|---|
| M0 | Baseline Repository | Phase 0 | durable initialization docs and templates | document review and internal consistency |
| M1 | First Closed Loop | Phase 1 | issue/event to PR proposal path | traceable end-to-end dry run with independent CI |
| M2 | Controlled Expansion Pack | Phase 2 | additional adapters and policy packs | repeated use without boundary collapse |
| M3 | Governance Evolution | Phase 3 | stronger policy, audit, and source diversity | reviewable governance and maintainable extension model |

## Open Questions
- What observability is essential in phase 1 versus phase 2?

## Change Log
- 2026-04-13: Initial version
- 2026-04-14: Refined baseline planning to externalize execution profiles and lifecycle traceability expectations.
- 2026-04-14: Documented first-target assumptions for Gitea, policy representation, and runtime isolation.
- 2026-04-14: Recorded selected Phase 1 directions for trigger path, policy layout, agent control, PR path, runtime egress, and traceability display.
- 2026-04-14: Synchronized selected Phase 1 detail defaults for command parsing, policy file schema, session record storage, and PR traceability conventions.
- 2026-04-15: Added a durable issue dashboard, archive, and supporting-note workflow to the Phase 0 baseline.
- 2026-04-15: Recorded the platform implementation-stack baseline for TypeScript/Node.js, npm, repo-owned Dockerfiles, and later compose packaging.
