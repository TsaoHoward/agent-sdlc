# Environment Requirements

## Purpose
This document defines the shared environment capability requirements for the repository.

It exists so environment expectations are defined before phases are scheduled, so Phase 1 and later phases build on a clear set of readiness criteria rather than on ad hoc assumptions.

## Goals
- define environment capabilities first, then derive phase sequencing from them
- make environment requirements concrete and verifiable
- keep environment requirements separate from implementation commands and bootstrap details
- centralize readiness gate criteria for project-local forge, control host, runtime, CI, and traceability
- preserve architecture boundary clarity while the environment evolves

## Non-Goals
- replacing architecture docs that define ownership and boundaries
- prescribing the final long-term runtime or deployment engine
- turning this document into a low-level provisioning script

## Requirement Model
Environment requirements are defined as capability items with acceptance criteria.

Each item should answer:
- what capability is required?
- why is it required for the first closed loop?
- what counts as minimum Phase 1 acceptance?
- which later phase topics depend on it?

Implementation details and current bootstrap commands belong in `docs/environment-bootstrap.md`.

## Overview
This repository separates environment planning from phase planning.

1. Define the environment capability requirements and their Phase 1 acceptance criteria.
2. Use those requirements as the baseline for Phase 0 and Phase 1 scheduling.
3. Only then split the work into phases and WBS items.

Phase 0 is therefore not just document writing; it is the work of making environment readiness observable and actionable.

## Shared Environment Inventory
| Environment ID | Name | Purpose | First Needed By | Primary WBS | Phase 1 Acceptance |
|---|---|---|---|---|---|
| ENV-001 | Forge Environment | Receive source events and host issues, branches, PRs, and review state | Phase 1 | WBS 3.1, 3.4, 3.5 | local forge available, event delivery, branch/PR automation, review gate |
| ENV-002 | Control Host | Run task gateway, session starter, and orchestrate handoff | Phase 1 | WBS 3.1, 3.2 | runnable Node.js control host, task intake, session start, persisted state |
| ENV-003 | Agent Runtime | Execute bounded agent work in isolated per-session containers | Phase 1 | WBS 3.3, 3.4 | worker image buildable, session container startable, workspace prepared |
| ENV-004 | CI Environment | Independently validate PR proposals | Phase 1 | WBS 3.5 | PR workflow runs, verification metadata produced, status visible |
| ENV-005 | Traceability And State Storage | Preserve task, session, and proposal-linked metadata | Phase 1 | WBS 3.2, 3.4, 3.6 | file-backed state and proposal traceability artifact exist |
| ENV-006 | Secret And Credential Surface | Provide minimum forge and workflow credentials to the right layers | Phase 1 | WBS 3.1, 3.2, 3.3, 3.5 | scoped secrets only, no broad default injection |
| ENV-007 | Future Deploy Environment | Remain downstream from agent execution and outside the Phase 1 closed loop | Phase 3+ | WBS 5+ | deferred for Phase 1 |

## Environment Requirements

### ENV-001 - Forge Environment
- Purpose:
  - host issues, comments, branches, PRs, and review state
  - deliver issue-comment events to the task gateway
  - provide a branch/PR automation surface for proposals
  - expose CI trigger capability and review gating
- Minimum Phase 1 acceptance:
  - local forge instance available and reachable from the control host
  - issue-comment event delivery path exists and can be exercised
  - repository branch and PR creation APIs are callable
  - PR status or review control exists so human review can remain a gate
- Current posture:
  - local Gitea bootstrap is scaffolded in repo-owned config
  - helper exists to provision a local owner/repo path for proposal flow testing
  - default bootstrap config now identifies the local development repo and its control-host callback URLs
  - repo bootstrap now ensures both issue-comment and review-follow-up webhooks exist for the default local repo
  - bootstrap settings now include explicit host ports and non-interactive install behavior
- Readiness check:
  - create a local issue and exercise an issue-comment webhook through the task gateway
  - submit a PR review or PR-close event and confirm the review-follow-up webhook path refreshes traceability
  - create a branch and PR from the proposal surface and verify it appears in local Gitea
- Primary source docs:
  - `docs/architecture/task-intake-contract.md`
  - `docs/architecture/pr-and-ci-path-definition.md`
  - `docs/decisions/ADR-0002-phase1-target-policy-and-runtime.md`

### ENV-002 - Control Host
- Purpose:
  - normalize source events into task requests
  - start agent sessions and track session state
  - persist state and hand off selected capabilities to runtime
- Minimum Phase 1 acceptance:
  - task gateway can normalize an issue comment event into a persisted task request
  - direct session starter can create a session record and prepare runtime handoff artifacts
  - task and session record persistence is observable under `.agent-sdlc/state/`
- Current posture:
  - npm-managed Node.js control-plane baseline exists
  - task gateway CLI and webhook listener commands are implemented
  - the local bootstrap now starts the default task-intake and review-follow-up webhook listeners as managed control-host services
  - direct session start CLI exists and writes agent session records
  - approval beyond auto-approved tasks is intentionally deferred
- Readiness check:
  - normalize a sample Gitea event and confirm `.agent-sdlc/state/task-requests/<id>.json`
  - run the local bootstrap in `-SkipGitea` mode and confirm both managed webhook listeners report healthy status
  - run `agent-control start-session` and confirm `.agent-sdlc/state/agent-sessions/<id>.json`
- Primary source docs:
  - `docs/architecture/agent-control-integration-plan.md`
  - `docs/architecture/task-intake-contract.md`

### ENV-003 - Agent Runtime
- Purpose:
  - execute bounded agent work in an isolated, per-session runtime
  - prepare a fresh session-local checkout and workspace
  - produce workspace artifacts that can be proposed and verified
- Minimum Phase 1 acceptance:
  - worker runtime image is buildable from repository Dockerfile
  - control host can launch a per-session worker container
  - a session-local workspace is created under `.agent-sdlc/runtime/workspaces/`
  - runtime launch metadata is written under `.agent-sdlc/runtime/artifacts/`
- Current posture:
  - initial worker-runtime Dockerfile exists
  - image scaffold has been built locally as `agent-sdlc-worker-runtime:test`
  - session starter prepares runtime launch artifacts and workspace paths
- Readiness check:
  - build worker runtime image successfully
  - start a runtime container and confirm the session workspace exists
- Primary source docs:
  - `docs/architecture/runtime-isolation.md`
  - `docs/decisions/ADR-0002-phase1-target-policy-and-runtime.md`
  - `docs/decisions/ADR-0003-phase1-runtime-egress-and-secret-defaults.md`

### ENV-004 - CI Environment
- Purpose:
  - independently validate proposed changes on the PR path
  - publish objective pass/fail status to the review surface
  - preserve proposal/task linkage in CI metadata
- Minimum Phase 1 acceptance:
  - PR-triggered workflow exists and can be executed
  - workflow produces verification metadata linked to the traceability artifact
  - CI result visibility is present in the PR or workflow output
- Current posture:
  - PR workflow skeleton defined in `.gitea/workflows/phase1-ci.yml`
  - local runner helper exists to adapt host-loopback network topology
  - current workflow runs npm validation and writes `.agent-sdlc/ci/verification-metadata.json`
- Readiness check:
  - execute the workflow for a proposal branch and confirm metadata output
  - confirm the workflow run is visible in local Gitea
- Primary source docs:
  - `docs/architecture/pr-and-ci-path-definition.md`
  - `docs/architecture/lifecycle-traceability-contract.md`

### ENV-005 - Traceability And State Storage
- Purpose:
  - persist task, session, proposal, CI, and review linkage
  - keep lifecycle state outside transient runtime memory
  - support later audit and review tracing
- Minimum Phase 1 acceptance:
  - state records exist under `.agent-sdlc/state/`
  - proposal traceability artifact exists under `.agent-sdlc/traceability/`
  - CI metadata output path is defined and populated
- Current posture:
  - file-backed state and traceability surfaces are scaffolded
  - proposal surface writes `.agent-sdlc/traceability/<task_request_id>.json`
  - verification metadata path is recognized by CI collection logic
- Readiness check:
  - validate that task/session/proposal records exist and reference each other
  - confirm traceability artifact is committed or staged into the proposal branch
- Primary source docs:
  - `docs/architecture/agent-control-integration-plan.md`
  - `docs/architecture/task-intake-contract.md`
  - `docs/architecture/lifecycle-traceability-contract.md`

### ENV-006 - Secret And Credential Surface
- Purpose:
  - provide the minimum credentials for forge, proposal, and CI operations
  - keep credential handling separate from runtime capability grants
- Minimum Phase 1 acceptance:
  - secrets are scoped and provided only when needed
  - secret injection is not the default path for Phase 1
  - credential handoff is explicit and auditable
- Current posture:
  - secret handling is documented as profile-specific
  - operator-provided environment variables are the current surface
- Readiness check:
  - confirm forge automation can operate with the configured credentials
  - verify no broad credentials are implicitly exposed to the worker runtime
- Primary source docs:
  - `docs/architecture/runtime-isolation.md`
  - `config/policy/runtime-capability-sets.yaml`
  - `docs/decisions/ADR-0003-phase1-runtime-egress-and-secret-defaults.md`

### ENV-007 - Future Deploy Environment
- Purpose:
  - support later release packaging and environment deployment
- Phase guidance:
  - not required for Phase 1 closed loop
  - remains downstream from agent execution and review
  - should not be coupled into the worker runtime or control plane at this stage
- Readiness check:
  - defer deploy environment readiness until Phase 3 planning
- Primary source docs:
  - `docs/architecture/overview.md`
  - `docs/project-overview.md`

## Phase Planning Based on Environment Requirements
1. Define the environment requirements and acceptance criteria.
2. Confirm Phase 1 acceptance gates for the required environment items.
3. Split the work into phases and WBS items that implement those gates.

This document therefore drives phase planning, not the other way around.

## Phase Mapping
| Phase | Environment Focus |
|---|---|
| Phase 0 | define environment requirements, architecture boundaries, and documented acceptance criteria |
| Phase 1 | implement the first closed loop on top of the defined Phase 1 environment requirements |
| Phase 2 | strengthen operational readiness, observability, and policy execution environment |
| Phase 3 | evolve toward remote worker models, deploy handoff, and broader governance |

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
- 2026-04-15: Added the Phase 1 project-local startup posture and linked the current bootstrap guidance.
- 2026-04-15: Recorded the local PostgreSQL-backed Gitea bootstrap default and updated environment readiness statuses for the current scaffold.
- 2026-04-15: Added repo-owned bootstrap config, explicit high-port forwarding, and non-interactive local Gitea installation guidance.
- 2026-04-15: Clarified that the bootstrap password-refresh path reapplies the tracked admin `mustChangePassword` setting to keep manual sign-in stable.
- 2026-04-15: Marked ENV-002 partially scaffolded after adding repo-local task-gateway and agent-control CLI entrypoints for file-backed task and session records.
- 2026-04-15: Recorded the selected platform implementation stack and packaging baseline for the control host and worker runtime.
- 2026-04-15: Marked the npm-managed control-plane baseline and first worker-runtime Dockerfile as implemented scaffolds.
- 2026-04-15: Updated ENV-002, ENV-003, and ENV-005 after landing webhook intake, retained source-event evidence, and per-session worker-runtime launch artifacts.
- 2026-04-16: Updated ENV-001, ENV-002, and ENV-005 after landing the local Gitea repo helper, proposal-surface CLI, and first PR-linked traceability artifact.
- 2026-04-16: Marked ENV-004 partially scaffolded after landing the local Gitea Actions runner helper, PR-triggered workflow skeleton, and verification-metadata output path.
- 2026-04-16: Updated ENV-004 after validating localhost-topology artifact upload in local Gitea run `#19` and narrowing the remaining gap to artifact listing visibility.
- 2026-04-21: Updated ENV-001 and ENV-002 after wiring the default local repo webhook set and bootstrap-managed control-host listeners into the local development posture.
