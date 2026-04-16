# Work Breakdown Structure (WBS)

## Document Metadata
- Version: 0.1
- Status: Draft
- Last Updated: 2026-04-16
- Owner: Project Maintainer
- Source Template: docs/templates/wbs.template.md

## WBS Rules
- WBS must align with `docs/roadmap.md`.
- Each work item should have a stable WBS ID.
- Each work item should produce a concrete deliverable.
- Dependencies must be explicit.
- Critical-path-candidate should be used only when delay would likely block downstream work.

---

## WBS Index
| WBS ID | Name | Parent | Related Phase | Deliverable |
|---|---|---|---|---|
| 1 | Project Baseline | - | Phase 0 | durable planning and architecture docs |
| 1.1 | Repository Guide Set | 1 | Phase 0 | README and AGENTS.md |
| 1.2 | Planning Document Set | 1 | Phase 0 | roadmap, WBS, prompt, operating model |
| 1.3 | Architecture Document Set | 1 | Phase 0 | architecture overview, context, lifecycle |
| 1.4 | Governance Document Set | 1 | Phase 0 | ADRs and policies with execution profiles and approval rules |
| 1.5 | Environment Requirements Baseline | 1 | Phase 0 | centralized environment inventory and readiness tracker |
| 1.6 | Issue Management Baseline | 1 | Phase 0 | issue dashboard, archive, and supporting-note workflow |
| 2 | Minimum Closed Loop Design | - | Phase 1 | design-ready interfaces and workflow definition |
| 2.1 | Task Intake Contract | 2 | Phase 1 | normalized task request definition with identifiers and policy refs |
| 2.2 | Agent Control Integration Plan | 2 | Phase 1 | control-plane interface plan |
| 2.3 | Execution Isolation Plan | 2 | Phase 1 | isolated runtime design |
| 2.4 | PR and CI Path Definition | 2 | Phase 1 | proposal and verification path definition |
| 2.5 | Lifecycle Traceability Contract | 2 | Phase 1 | cross-layer identifier and handoff definition |
| 3 | Minimum Closed Loop Implementation | - | Phase 1 | first working end-to-end path |
| 3.1 | Trigger Adapter Implementation | 3 | Phase 1 | one working trigger path |
| 3.2 | Agent Session Starter | 3 | Phase 1 | working session launch path |
| 3.3 | Worker Runtime Scaffold | 3 | Phase 1 | isolated execution scaffold |
| 3.4 | PR Proposal Path | 3 | Phase 1 | branch/PR proposal flow with task/session linkage |
| 3.5 | CI Verification Skeleton | 3 | Phase 1 | independent CI workflow with proposal/task linkage |
| 3.6 | Lifecycle Traceability Scaffold | 3 | Phase 1 | minimal end-to-end traceability record |
| 4 | Controlled Expansion | - | Phase 2 | structured expansion without boundary collapse |
| 4.1 | Additional Intake Paths | 4 | Phase 2 | more adapters |
| 4.2 | Policy Pack Expansion | 4 | Phase 2 | richer policy definitions |
| 4.3 | Observability and Audit | 4 | Phase 2 | lifecycle visibility improvements |
| 5 | Governance Evolution | - | Phase 3 | stronger governance and replaceability model |
| 5.1 | Governance Model Refinement | 5 | Phase 3 | expanded governance rules |
| 5.2 | Component Replaceability Review | 5 | Phase 3 | replaceability assessment/update |
| 5.3 | Multi-Source Support Planning | 5 | Phase 3 | broader source integration plan |

---

## Work Items

### WBS 1 — Project Baseline
- Parent:
- Related Phase: Phase 0
- Description: Establish the durable repository baseline used by future humans and agents.
- Deliverable: Initialized core document set and templates.
- Dependencies:
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: This is the foundation for all later work.

### WBS 1.1 — Repository Guide Set
- Parent: 1
- Related Phase: Phase 0
- Description: Create repository entry and agent behavior guidance.
- Deliverable: `README.md`, `AGENTS.md`
- Dependencies:
- Critical-Path-Candidate: Yes
- Status: Done
- Notes:

### WBS 1.2 — Planning Document Set
- Parent: 1
- Related Phase: Phase 0
- Description: Establish maintainable roadmap, WBS, prompt, and operating model artifacts.
- Deliverable: `docs/roadmap.md`, `docs/wbs.md`, `docs/operating-model.md`, `prompts/init-project.prompt.md`
- Dependencies: 1.1
- Critical-Path-Candidate: Yes
- Status: Done
- Notes:

### WBS 1.3 — Architecture Document Set
- Parent: 1
- Related Phase: Phase 0
- Description: Capture system boundaries, context, and task lifecycle.
- Deliverable: `docs/architecture/overview.md`, `docs/architecture/system-context.md`, `docs/architecture/task-lifecycle.md`
- Dependencies: 1.1
- Critical-Path-Candidate: Yes
- Status: Done
- Notes:

### WBS 1.4 — Governance Document Set
- Parent: 1
- Related Phase: Phase 0
- Description: Record initial boundary decisions, intake rules, approval rules, and execution-profile guidance.
- Deliverable: `docs/decisions/ADR-0001-system-boundaries.md`, policy docs with execution profiles and traceability rules
- Dependencies: 1.1, 1.3
- Critical-Path-Candidate: Yes
- Status: Done
- Notes:

### WBS 1.5 — Environment Requirements Baseline
- Parent: 1
- Related Phase: Phase 0
- Description: Maintain one centralized document for shared environment requirements, first-needed phase, and implementation mapping.
- Deliverable: `docs/environment-requirements.md`
- Dependencies: 1.2, 1.3, 1.4
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: This document centralizes environment needs and defines concrete Phase 1 acceptance criteria that drive later phase decomposition and implementation planning.

### WBS 1.6 ??Issue Management Baseline
- Parent: 1
- Related Phase: Phase 0
- Description: Establish a durable dashboard, archive, and supporting-note workflow for active project issues that need cross-run visibility without replacing forge issue history or roadmap/WBS structure.
- Deliverable: `docs/issues/issue-dashboard.md`, `docs/issues/issue-archive.md`, issue templates, and issue-management policy
- Dependencies: 1.2, 1.4
- Critical-Path-Candidate: No
- Status: Done
- Notes: This issue workflow complements the forge issue surface, WBS, and decision backlog rather than replacing them.

### WBS 2 — Minimum Closed Loop Design
- Parent:
- Related Phase: Phase 1
- Description: Define the smallest design-ready path from task intake to verified proposal.
- Deliverable: design-level contracts and path definitions
- Dependencies: 1
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: Phase 1 design baseline now includes task intake, runtime isolation, agent-control integration, PR/CI path, and lifecycle traceability.

### WBS 2.1 — Task Intake Contract
- Parent: 2
- Related Phase: Phase 1
- Description: Define the normalized task request model, required metadata, stable identifiers, and acceptance constraints.
- Deliverable: task request schema/spec with policy references and execution-profile linkage
- Dependencies: 1.3, 1.4
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: Spec is documented in `docs/architecture/task-intake-contract.md` and aligned to ADR-0002.

### WBS 2.2 — Agent Control Integration Plan
- Parent: 2
- Related Phase: Phase 1
- Description: Define how the task gateway starts and tracks agent sessions.
- Deliverable: control-plane interface plan
- Dependencies: 2.1
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: Spec is documented in `docs/architecture/agent-control-integration-plan.md`.

### WBS 2.3 — Execution Isolation Plan
- Parent: 2
- Related Phase: Phase 1
- Description: Define the first isolated execution runtime and its boundaries.
- Deliverable: runtime isolation design
- Dependencies: 2.1
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: First-phase runtime isolation strategy is documented in ADR-0002 and `docs/architecture/runtime-isolation.md`.

### WBS 2.4 — PR and CI Path Definition
- Parent: 2
- Related Phase: Phase 1
- Description: Define how proposed changes are surfaced, linked to their source task/session, and verified.
- Deliverable: PR/CI path definition
- Dependencies: 2.2, 2.3
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: Spec is documented in `docs/architecture/pr-and-ci-path-definition.md`.

### WBS 2.5 — Lifecycle Traceability Contract
- Parent: 2
- Related Phase: Phase 1
- Description: Define the minimum identifiers and handoff metadata that connect event, task, session, proposal, CI, and review records.
- Deliverable: cross-layer traceability contract
- Dependencies: 2.1, 2.2, 2.4
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: Spec is documented in `docs/architecture/lifecycle-traceability-contract.md`.

### WBS 3 — Minimum Closed Loop Implementation
- Parent:
- Related Phase: Phase 1
- Description: Implement the first end-to-end working path.
- Deliverable: one working closed loop
- Dependencies: 2
- Critical-Path-Candidate: Yes
- Status: In Progress
- Notes: Project-local environment bootstrap now includes repo-owned config, explicit high-port forwarding, non-interactive local Gitea initialization, and admin-password refresh behavior that preserves the tracked forced-password-change setting so the first implementation slice can start without unstable manual forge setup. The current implementation slice now also includes repo-local task-gateway, agent-control, proposal-surface, and local-Gitea-repo helper CLIs that write file-backed task/session state and create the first traceable Gitea PR proposal. ADR-0006 now sets the platform-stack convergence path to TypeScript/Node.js plus npm, with repo-owned Dockerfiles as the packaging baseline before later compose consolidation.

### WBS 3.1 — Trigger Adapter Implementation
- Parent: 3
- Related Phase: Phase 1
- Description: Implement one supported intake path from an external event into task normalization.
- Deliverable: working intake adapter
- Dependencies: 2.1
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: A working Gitea issue-comment trigger path now exists. The repo-local task gateway still supports file-backed normalization for examples, and it now also exposes `node scripts/task-gateway.js serve-gitea-webhook ...` for actual webhook delivery, retained source-event evidence, normalized task-request persistence, and direct session-start handoff for auto-approved requests.

### WBS 3.2 — Agent Session Starter
- Parent: 3
- Related Phase: Phase 1
- Description: Start a bounded agent session using the normalized task request and policy context.
- Deliverable: working agent session starter
- Dependencies: 2.2
- Critical-Path-Candidate: Yes
- Status: In Progress
- Notes: A direct session-start CLI now exists at `node scripts/agent-control.js start-session --task-request <path>`, writes session records under `.agent-sdlc/state/agent-sessions/`, and now performs runtime handoff into the worker container scaffold. A repo-owned npm baseline also exists via `package.json`, `package-lock.json`, and `tsconfig.json`. Remaining work is to assemble fuller session context for actual agent execution and carry the session forward into proposal creation.

### WBS 3.3 — Worker Runtime Scaffold
- Parent: 3
- Related Phase: Phase 1
- Description: Stand up the initial isolated workspace/runtime scaffold.
- Deliverable: working isolated runtime scaffold
- Dependencies: 2.3
- Critical-Path-Candidate: Yes
- Status: In Progress
- Notes: The first repo-owned worker-runtime Dockerfile now exists at `docker/worker-runtime/Dockerfile`, has been built locally as `agent-sdlc-worker-runtime:test`, and is now exercised by `agent-control start-session` for a real per-session runtime launch path. The current slice prepares a session-local workspace checkout plus runtime-launch artifacts under `.agent-sdlc/runtime/`. Remaining work is to use that prepared workspace for branch/PR proposal flow and later execution steps.

### WBS 3.4 — PR Proposal Path
- Parent: 3
- Related Phase: Phase 1
- Description: Surface the agent's bounded change as a branch and PR or equivalent proposal with source-task linkage.
- Deliverable: working proposal path with task/session references
- Dependencies: 3.1, 3.2, 3.3
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: A working proposal path now exists at `node scripts/proposal-surface.js create-gitea-pr --session <path>`. The current slice reads the prepared session/task records, force-adds `.agent-sdlc/traceability/<task_request_id>.json` inside the prepared workspace, pushes `agent/<task_request_id>` to Gitea, and creates or updates the linked PR with the reviewer-facing traceability block.

### WBS 3.5 — CI Verification Skeleton
- Parent: 3
- Related Phase: Phase 1
- Description: Independently validate the proposed change through CI and retain linkage to the proposal and originating task.
- Deliverable: working CI skeleton with proposal/task linkage
- Dependencies: 2.4, 3.4
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: The first PR-triggered CI workflow now exists at `.gitea/workflows/phase1-ci.yml`, and the repo-local runner helper now exists at `node scripts/dev/ensure-local-gitea-runner.js ensure-runner`. The current workflow collects `.agent-sdlc/ci/verification-metadata.json` from the proposal branch, runs `npm ci`, `npm run validate:platform`, and `npm run typecheck`, and was smoke-tested successfully against the local Gitea stack with run `#19` completing successfully after the localhost-rooted topology was updated to use host networking plus an injected `agent-sdlc-gitea` host alias for runner-triggered job containers. Uploaded artifact chunks now persist in local Gitea storage, while operator-facing artifact listing visibility remains a narrower follow-up.

### WBS 3.6 — Lifecycle Traceability Scaffold
- Parent: 3
- Related Phase: Phase 1
- Description: Implement the minimum record or metadata path that preserves traceability from event intake through human review.
- Deliverable: minimal end-to-end traceability scaffold
- Dependencies: 2.5, 3.2, 3.4, 3.5
- Critical-Path-Candidate: Yes
- Status: In Progress
- Notes: The first proposal-linked traceability artifact now exists. `proposal-surface create-gitea-pr` writes `.agent-sdlc/traceability/<task_request_id>.json` into the proposal branch and records `proposal_ref` / `proposal_url` back into the session record. CI now extends that linkage by generating `.agent-sdlc/ci/verification-metadata.json` plus reviewer-visible job-log and step-summary metadata containing `task_request_id`, `proposal_ref`, and the linked session/source identifiers. Remaining work is to write CI run references back into longer-lived traceability surfaces and extend the linkage through human review outcome.

### WBS 4 — Controlled Expansion
- Parent:
- Related Phase: Phase 2
- Description: Broaden capabilities while preserving architecture boundaries.
- Deliverable: controlled expansion plan and/or implementation
- Dependencies: 3
- Critical-Path-Candidate: No
- Status: Not Started
- Notes:

### WBS 4.1 — Additional Intake Paths
- Parent: 4
- Related Phase: Phase 2
- Description: Support more trigger sources without changing the task model's meaning.
- Deliverable: additional adapters
- Dependencies: 3.1
- Critical-Path-Candidate: No
- Status: Not Started
- Notes:

### WBS 4.2 — Policy Pack Expansion
- Parent: 4
- Related Phase: Phase 2
- Description: Expand reusable policy and context definitions.
- Deliverable: richer policy packs
- Dependencies: 1.4, 3
- Critical-Path-Candidate: No
- Status: Not Started
- Notes:

### WBS 4.3 — Observability and Audit
- Parent: 4
- Related Phase: Phase 2
- Description: Improve lifecycle visibility, auditability, and failure tracing.
- Deliverable: audit and observability improvements
- Dependencies: 3
- Critical-Path-Candidate: No
- Status: Not Started
- Notes:

### WBS 5 — Governance Evolution
- Parent:
- Related Phase: Phase 3
- Description: Mature governance and long-term replaceability rules.
- Deliverable: governance and replaceability refinement
- Dependencies: 4
- Critical-Path-Candidate: No
- Status: Not Started
- Notes:

### WBS 5.1 — Governance Model Refinement
- Parent: 5
- Related Phase: Phase 3
- Description: Formalize approval, escalation, and durable control rules.
- Deliverable: refined governance model
- Dependencies: 4.2, 4.3
- Critical-Path-Candidate: No
- Status: Not Started
- Notes:

### WBS 5.2 — Component Replaceability Review
- Parent: 5
- Related Phase: Phase 3
- Description: Reassess layer boundaries and replacement cost for major components.
- Deliverable: replaceability review/update
- Dependencies: 4
- Critical-Path-Candidate: No
- Status: Not Started
- Notes:

### WBS 5.3 — Multi-Source Support Planning
- Parent: 5
- Related Phase: Phase 3
- Description: Plan broader intake sources and long-term orchestration evolution.
- Deliverable: multi-source support plan
- Dependencies: 4.1, 5.1
- Critical-Path-Candidate: No
- Status: Not Started
- Notes:

---

## Dependency View
| WBS ID | Depends On | Why |
|---|---|---|
| 1.2 | 1.1 | planning docs need repo entry and agent rules |
| 1.3 | 1.1 | architecture docs depend on shared repo framing |
| 1.4 | 1.1, 1.3 | governance docs depend on repo framing and system boundaries |
| 1.5 | 1.2, 1.3, 1.4 | environment baseline depends on planning, architecture, and governance context |
| 1.6 | 1.2, 1.4 | issue-management baseline depends on planning structure and governance rules |
| 2 | 1 | design starts after baseline exists |
| 2.1 | 1.3, 1.4 | intake contract depends on boundaries and policies |
| 2.2 | 2.1 | control integration depends on task model |
| 2.3 | 2.1 | runtime boundary depends on task model |
| 2.4 | 2.2, 2.3 | proposal/CI path depends on control and runtime design |
| 2.5 | 2.1, 2.2, 2.4 | traceability depends on task, control, and proposal/verification seams |
| 3 | 2 | implementation follows design |
| 3.1 | 2.1 | intake implementation depends on intake contract |
| 3.2 | 2.2 | session starter depends on control plan |
| 3.3 | 2.3 | runtime scaffold depends on isolation plan |
| 3.4 | 3.1, 3.2, 3.3 | proposal path depends on intake, control, and runtime |
| 3.5 | 2.4, 3.4 | CI path depends on proposal definition and working proposal path |
| 3.6 | 2.5, 3.2, 3.4, 3.5 | traceability scaffold depends on designed identifiers and working lifecycle checkpoints |
| 4 | 3 | expansion should follow first working loop |
| 5 | 4 | governance evolution should follow practical expansion experience |

## Critical Path Candidates
- 1
- 1.1
- 1.2
- 1.3
- 1.4
- 1.5
- 2
- 2.1
- 2.2
- 2.3
- 2.4
- 2.5
- 3
- 3.1
- 3.2
- 3.3
- 3.4
- 3.5
- 3.6

## Open Questions
- No current WBS-level open questions block WBS 3 start.

## Change Log
- 2026-04-13: Initial version
- 2026-04-14: Marked phase-0 baseline items done and added explicit phase-1 traceability planning work.
- 2026-04-14: Marked runtime isolation strategy as designed and aligned phase-1 assumptions to ADR-0002.
- 2026-04-14: Marked agent control and PR/CI design items done and aligned remaining open questions to implementation detail.
- 2026-04-14: Cleared the remaining WBS-level pre-implementation detail blockers after selecting the command contract, policy schema, and minimum CI policy defaults.
- 2026-04-14: Added a centralized environment requirements baseline so shared environment work can be tracked outside phase-specific implementation notes.
- 2026-04-15: Added a Phase 0 issue-management baseline for durable active-issue tracking, archive, and supporting-note workflow.
- 2026-04-15: Marked WBS 3 in progress after adding the initial project-local environment bootstrap scaffold for the first implementation slice.
- 2026-04-15: Expanded the WBS 3 bootstrap note to reflect repo-owned config, explicit high-port forwarding, and non-interactive local Gitea initialization.
- 2026-04-15: Updated the WBS 3 bootstrap note to capture the admin-password refresh fix that keeps manual Gitea sign-in out of the forced password-change flow unless configured.
- 2026-04-15: Marked WBS 3.1 and 3.2 in progress after adding repo-local task-gateway and session-starter CLI scaffolds for file-backed task and session records.
- 2026-04-15: Recorded ADR-0006 implications for the platform stack, npm management path, and worker Dockerfile expectations in WBS 3.
- 2026-04-15: Marked the npm-managed platform baseline implemented and moved WBS 3.3 to in progress after adding and locally building the first worker-runtime Dockerfile.
- 2026-04-15: Marked WBS 3.1 done after landing the webhook-backed trigger path and updated WBS 3.2 and 3.3 to reflect runtime handoff into the worker image scaffold.
- 2026-04-16: Marked WBS 3.4 done and WBS 3.6 in progress after landing the first branch/PR proposal path and proposal-linked traceability artifact.
- 2026-04-16: Marked WBS 3.5 done after landing the local Gitea Actions runner helper, PR-triggered CI workflow skeleton, and verification-metadata linkage.
