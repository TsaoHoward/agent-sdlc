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

## Phase 1 Startup Posture
Phase 1 does not require every environment dependency to be packaged inside the repository itself from day one.

It does require a project-local operator surface so maintainers can bring up the current development stack from repository entrypoints instead of rebuilding ad hoc commands for each run.

The initial bootstrap approach may therefore:
- use repository-owned scripts as the stable startup surface
- call external tools or services such as Docker where practical
- keep `docker compose` or an equivalent one-command launcher as a later consolidation option once the actual service mix is stable

See `docs/environment-bootstrap.md` for the current bootstrap entrypoints and their scope.

## Shared Environment Inventory
| Environment ID | Name | Purpose | First Needed By | Primary WBS | Current Status |
|---|---|---|---|---|---|
| ENV-001 | Forge Environment | Receive source events and host issues, branches, PRs, and review state | Phase 1 | WBS 3.1, 3.4, 3.5 | Partially Scaffolded |
| ENV-002 | Control Host | Run task gateway and direct session starter | Phase 1 | WBS 3.1, 3.2 | Partially Scaffolded |
| ENV-003 | Worker Runtime | Execute bounded agent work in isolated per-session containers | Phase 1 | WBS 3.3, 3.4 | Partially Scaffolded |
| ENV-004 | CI Environment | Independently validate PR proposals | Phase 1 | WBS 3.5 | Partially Scaffolded |
| ENV-005 | Traceability And State Storage | Preserve task, session, and proposal-linked metadata | Phase 1 | WBS 3.2, 3.4, 3.6 | Bootstrap Scaffolded |
| ENV-006 | Secret And Credential Surface | Provide minimum forge and workflow credentials to the right layers | Phase 1 | WBS 3.1, 3.2, 3.3, 3.5 | Defined |
| ENV-007 | Future Deploy Environment | Remain downstream from agent execution and outside the Phase 1 closed loop | Phase 3+ | WBS 5+ | Deferred |

## Environment Requirements

### ENV-001 - Forge Environment
- Initial target: Gitea
- Current bootstrap posture:
  - local project bootstrap defaults to a PostgreSQL-backed Gitea stack
  - SQLite remains an allowed lighter-weight fallback for narrow local bring-up
  - local host access uses explicit forwarded high ports from `config/dev/gitea-bootstrap.json` instead of relying on common defaults
  - the current bootstrap path avoids manual web install by applying tracked settings and creating the bootstrap admin user non-interactively
  - bootstrap password refresh also reapplies the tracked admin `mustChangePassword` flag so manual sign-in does not drift into a forced password-change flow unless explicitly configured
  - a repo-local helper now exists at `node scripts/dev/ensure-local-gitea-repo.js ensure-local-repo --owner <owner> --repo <repo> --seed-from <path>` so the Phase 1 proposal path can target a known local Gitea repository during development
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
- Implementation-stack baseline:
  - the platform control host should converge on `TypeScript` running on `Node.js LTS`
  - repo-owned Node-based platform code should move under `npm` management as the current CLI scaffolds become a formal package
  - local bootstrap wrappers may remain in PowerShell without redefining the platform's primary service stack
- Current bootstrap posture:
  - repo-owned `package.json`, `package-lock.json`, and `tsconfig.json` now define the npm-managed control-plane baseline
  - repo-local control-host entrypoints now exist at `node scripts/task-gateway.js normalize-gitea-issue-comment --event <path>`, `node scripts/task-gateway.js serve-gitea-webhook ...`, `node scripts/agent-control.js start-session --task-request <path>`, and `node scripts/proposal-surface.js create-gitea-pr --session <path>`
  - the current implementation uses plain Node.js CLI scaffolds as an early slice on the selected TypeScript/Node.js convergence path
  - actual Gitea issue-comment webhook delivery now lands on the repo-local task gateway, which persists retained source-event evidence plus normalized task requests before calling the direct session starter
  - the proposal surface now reads the prepared session/task records, force-adds the linked traceability artifact inside the prepared workspace, pushes `agent/<task_request_id>` to Gitea, and creates or updates the PR
  - approval handling beyond auto-approved tasks remains a later slice
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
- Packaging baseline:
  - the first worker runtime should become a repo-owned container image defined by a Dockerfile
  - worker packaging should remain separate from the control-plane image so runtime isolation stays reviewable and explicit
- Current bootstrap posture:
  - the first worker-runtime Dockerfile now exists at `docker/worker-runtime/Dockerfile`
  - the current image scaffold has been built locally as `agent-sdlc-worker-runtime:test`
  - the current session starter now launches that image as a per-session container, prepares a fresh workspace checkout under `.agent-sdlc/runtime/workspaces/`, and exports runtime-launch artifacts under `.agent-sdlc/runtime/artifacts/`
  - remaining work is to connect the prepared worker workspace to the proposal path and later execution steps
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
- Current bootstrap posture:
  - the first PR-triggered workflow now exists at `.gitea/workflows/phase1-ci.yml`
  - the repo-local runner helper now exists at `node scripts/dev/ensure-local-gitea-runner.js ensure-runner` and adapts the runner and job-container network mode when the tracked local forge base URL points to host loopback
  - the current workflow runs `npm ci`, `npm run validate:platform`, and `npm run typecheck`, then writes verification linkage to `.agent-sdlc/ci/verification-metadata.json`
  - the current local smoke-test baseline has been exercised successfully against the local Gitea instance, with verification metadata visible in job logs, step summaries, and a persisted workflow artifact after validation run `#19`
  - the localhost-rooted topology now succeeds by using host networking plus an injected `agent-sdlc-gitea` host alias for job containers, although local artifact listing visibility in Gitea still needs follow-up if operator browsing becomes important
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
  - `.agent-sdlc/state/source-events/<source_event_record_id>.json`
  - `.agent-sdlc/state/task-requests/<task_request_id>.json`
  - `.agent-sdlc/state/agent-sessions/<agent_session_id>.json`
  - `.agent-sdlc/runtime/artifacts/<agent_session_id>/runtime-launch.json`
  - proposal-branch artifact at `.agent-sdlc/traceability/<task_request_id>.json`
  - workflow-created verification metadata at `.agent-sdlc/ci/verification-metadata.json`
  - local prepared-workspace mirror at `.agent-sdlc/runtime/workspaces/<agent_session_id>/.agent-sdlc/traceability/<task_request_id>.json`
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
