# Environment Requirements

## Purpose
This document centralizes the environment requirements for the project across planning, implementation, verification, and later evolution.

It exists so environment expectations do not stay fragmented across phase-specific WBS items or architecture notes.

## Goals
- provide one durable source of truth for project environment needs
- separate environment inventory from phase-specific implementation sequencing
- make shared environment dependencies easy to assign, track, and review
- keep environment planning aligned with the layered architecture

## Non-Goals
- replacing the architecture docs that define ownership and boundaries
- selecting the final long-term platform for every layer
- defining low-level host provisioning scripts in Phase 1

## Environment Tracking Model
Use this document as the centralized environment tracker.

Environment work may still be implemented through multiple WBS items, but:
- the requirement definition lives here
- roadmap and WBS should reference this document rather than restating full environment details
- status here should describe environment readiness, not only document completeness

## Shared Environment Inventory
| Environment ID | Name | Purpose | First Needed By | Primary WBS | Current Status |
|---|---|---|---|---|---|
| ENV-001 | Forge Environment | Receive source events and host issues, branches, PRs, and review state | Phase 1 | WBS 3.1, 3.4, 3.5 | Defined |
| ENV-002 | Control Host | Run task gateway and direct session starter | Phase 1 | WBS 3.1, 3.2 | Defined |
| ENV-003 | Worker Runtime | Execute bounded agent work in isolated per-session containers | Phase 1 | WBS 3.3, 3.4 | Defined |
| ENV-004 | CI Environment | Independently validate PR proposals | Phase 1 | WBS 3.5 | Defined |
| ENV-005 | Traceability And State Storage | Preserve task, session, and proposal-linked metadata | Phase 1 | WBS 3.2, 3.4, 3.6 | Defined |
| ENV-006 | Secret And Credential Surface | Provide minimum forge and workflow credentials to the right layers | Phase 1 | WBS 3.1, 3.2, 3.3, 3.5 | Defined |
| ENV-007 | Future Deploy Environment | Remain downstream from agent execution and outside the Phase 1 closed loop | Phase 3+ | WBS 5+ | Deferred |

## Environment Requirements

### ENV-001 - Forge Environment
- Initial target: Gitea
- Responsibilities:
  - source issue comment events
  - repository and branch surface
  - PR creation and review surface
  - CI trigger attachment surface
- Minimum requirements:
  - repository with issue and PR support
  - webhook or equivalent event delivery for issue comments
  - API or automation path for branch and PR creation
  - branch protection or equivalent merge controls so human review remains the gate
- Primary source docs:
  - `docs/architecture/task-intake-contract.md`
  - `docs/architecture/pr-and-ci-path-definition.md`
  - `docs/decisions/ADR-0002-phase1-target-policy-and-runtime.md`

### ENV-002 - Control Host
- Responsibilities:
  - receive normalized task intake flow
  - run the direct session starter
  - persist task and session records outside transient memory
  - hand off selected capability sets into runtime
- Minimum requirements:
  - ability to run the task gateway implementation
  - ability to invoke `agent-control start-session --task-request <path>`
  - access to repository policy/config/docs needed for context assembly
  - access to the local container runner used for worker startup
- Recommended Phase 1 posture:
  - single trusted orchestration host is acceptable
  - separate service decomposition is not required yet
- Primary source docs:
  - `docs/architecture/agent-control-integration-plan.md`
  - `docs/architecture/task-intake-contract.md`

### ENV-003 - Worker Runtime
- Initial target: host-local Docker-compatible container runner
- Responsibilities:
  - create one isolated worker per accepted task/session
  - prepare fresh session-local checkout/workspace
  - execute bounded commands under the selected capability set
  - export approved artifacts only
- Minimum requirements:
  - container runner available to the control host
  - non-root execution inside the worker
  - no host Docker socket exposed inside the worker
  - session-local workspace rather than direct host developer workspace binding
- Phase 1 defaults:
  - broad egress is temporarily allowed
  - dependency caches are not mounted by default
  - explicit artifact export is required
- Primary source docs:
  - `docs/architecture/runtime-isolation.md`
  - `docs/decisions/ADR-0002-phase1-target-policy-and-runtime.md`
  - `docs/decisions/ADR-0003-phase1-runtime-egress-and-secret-defaults.md`

### ENV-004 - CI Environment
- Responsibilities:
  - run independent verification on the PR path
  - publish objective pass/fail status to the review surface
  - preserve proposal/task linkage in CI metadata
- Minimum requirements:
  - PR-triggered workflow support
  - required workflow enforcement for agent-opened PRs
  - visibility of CI outcome in the PR surface
- Phase 1 trigger expectations:
  - PR open
  - PR update / synchronize
  - PR reopen
- Primary source docs:
  - `docs/architecture/pr-and-ci-path-definition.md`
  - `docs/architecture/lifecycle-traceability-contract.md`

### ENV-005 - Traceability And State Storage
- Responsibilities:
  - persist normalized task request records
  - persist session records
  - persist proposal-linked traceability artifact references
- Minimum requirements:
  - file-backed JSON records under `.agent-sdlc/state/`
  - proposal-linked metadata artifact under `.agent-sdlc/traceability/`
  - retention long enough to cover PR lifecycle and short post-completion review
- Phase 1 record paths:
  - `.agent-sdlc/state/task-requests/<task_request_id>.json`
  - `.agent-sdlc/state/agent-sessions/<agent_session_id>.json`
  - `.agent-sdlc/traceability/<task_request_id>.json`
- Primary source docs:
  - `docs/architecture/agent-control-integration-plan.md`
  - `docs/architecture/task-intake-contract.md`
  - `docs/architecture/lifecycle-traceability-contract.md`

### ENV-006 - Secret And Credential Surface
- Responsibilities:
  - supply the minimum credentials needed for forge, PR, or CI-related actions
  - keep broad runtime network access separate from credential access
- Minimum requirements:
  - no secret injection unless the selected profile requires it
  - scoped credentials only
  - ability to withhold secrets from investigation-only or escalation-hold profiles
- Phase 1 expectation:
  - secret handling remains profile-specific and intentionally minimal
- Primary source docs:
  - `docs/architecture/runtime-isolation.md`
  - `config/policy/runtime-capability-sets.yaml`
  - `docs/decisions/ADR-0003-phase1-runtime-egress-and-secret-defaults.md`

### ENV-007 - Future Deploy Environment
- Responsibilities:
  - release packaging, promotion, and environment deployment
- Phase guidance:
  - not part of the Phase 1 closed loop
  - remains downstream from agent execution
  - should not be coupled into the worker runtime or agent control plane
- Primary source docs:
  - `docs/architecture/overview.md`
  - `docs/project-overview.md`

## Phase Mapping
| Phase | Environment Focus |
|---|---|
| Phase 0 | define environment requirements and boundaries without overcommitting platform specifics |
| Phase 1 | stand up forge, control host, worker runtime, CI, and file-backed traceability for the first closed loop |
| Phase 2 | improve observability, richer policy packs, and stronger operational handling |
| Phase 3 | revisit remote workers, broader orchestration, and stronger long-term governance/deploy handoff |

## WBS Mapping Guidance
Environment requirements are centralized here, but implementation responsibility stays distributed:
- WBS `3.1` consumes ENV-001, ENV-002, and ENV-006 for intake and forge connectivity
- WBS `3.2` consumes ENV-002, ENV-005, and ENV-006 for session startup and record persistence
- WBS `3.3` consumes ENV-003 and ENV-006 for isolated runtime execution
- WBS `3.4` consumes ENV-001, ENV-003, and ENV-005 for proposal creation and metadata surfacing
- WBS `3.5` consumes ENV-001 and ENV-004 for independent PR verification
- WBS `3.6` consumes ENV-005 across the lifecycle

## Current Open Questions
- how much task routing should remain in repo config versus move into service config later?
- what observability beyond minimum traceability should be deferred until Phase 2?
- when should the first runner move from host-local containers to a remote worker model?

## Change Control Guidance
- update this document when a new shared environment becomes required
- update this document when first-needed phase or ownership changes
- update roadmap and WBS references when environment sequencing changes
- create or update an ADR if environment changes affect system boundaries, ownership, runtime isolation assumptions, CI ownership, or deployment responsibility

## Change Log
- 2026-04-14: Initial version.
