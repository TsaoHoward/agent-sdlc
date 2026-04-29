# Work Breakdown Structure (WBS)

## Document Metadata
- Version: 0.1
- Status: Draft
- Last Updated: 2026-04-29
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
| 3.7 | Testing Workflow Baseline | 3 | Phase 1 | repeatable local test plan, dashboard, and canonical CLI/GUI procedures |
| 3.8 | User Capability Matrix | 3 | Phase 1 | durable user-facing matrix for supported `@agent` and operator workflows |
| 3.9 | Minimal Real Agent Execution | 3 | Phase 1 | one provider-backed bounded execution path for a supported task class |
| 3.10 | External Target Repo Evaluation Baseline | 3 | Phase 1 | distinct target-repo baseline for service evaluation beyond platform self-test |
| 3.11 | Service-State And Evaluation Workflow | 3 | Phase 1 | durable workbench/internal-eval/pilot/production model with evidence rules |
| 4 | Controlled Expansion | - | Phase 2 | structured expansion without boundary collapse |
| 4.1 | Additional Intake Paths | 4 | Phase 2 | more adapters |
| 4.2 | Policy Pack Expansion | 4 | Phase 2 | richer policy definitions |
| 4.3 | Observability and Audit | 4 | Phase 2 | lifecycle visibility improvements |
| 4.4 | Pilot Promotion Gates | 4 | Phase 2 | staged rollout rules for target repos, task classes, and user exposure |
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
- Notes: ADR-0008 and `docs/policies/configuration-management.md` now define the repository-wide rule that configurable modules should use checked-in templates plus ignored local config when values may vary per operator or environment.

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
- Notes: Project-local environment bootstrap now includes a repo-owned template plus ignored local config path, explicit high-port forwarding, non-interactive local Gitea initialization, and admin-password refresh behavior that preserves the configured forced-password-change setting so the first implementation slice can start without unstable manual forge setup. The current implementation slice now also includes repo-local task-gateway, agent-control, proposal-surface, and local-Gitea-repo helper CLIs that write file-backed task/session state and create the first traceable Gitea PR proposal. ADR-0006 now sets the platform-stack convergence path to TypeScript/Node.js plus npm, with repo-owned Dockerfiles as the packaging baseline before later compose consolidation. ADR-0009 now also clarifies that the seeded local `agent-sdlc` repo path is valid platform regression evidence but is not sufficient by itself as long-term service-quality evidence for non-platform target repositories. Phase 1 close-out remains open because the provider-backed docs path still needs a guardrail against large-file truncation under the current `maxFileBytes` plus full-file-response contract.

### WBS 3.1 — Trigger Adapter Implementation
- Parent: 3
- Related Phase: Phase 1
- Description: Implement one supported intake path from an external event into task normalization.
- Deliverable: working intake adapter
- Dependencies: 2.1
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: A working Gitea issue-comment trigger path now exists. The repo-local task gateway still supports file-backed normalization for examples, and it now also exposes `node scripts/task-gateway.js serve-configured-gitea-webhook` for actual webhook delivery using template/local bootstrap settings, retained source-event evidence, normalized task-request persistence, and direct session-start handoff for auto-approved requests. The local bootstrap now starts the default task-gateway webhook listener, ensures the default local repo is wired to the matching issue-comment callback, and sets a local Gitea webhook allowlist that admits the Docker-private host callback used by `host.docker.internal`. The live path now also supports bounded issue-thread feedback comments for malformed command rejection and failed live continuation states so common operator mistakes do not look silent.

### WBS 3.2 — Agent Session Starter
- Parent: 3
- Related Phase: Phase 1
- Description: Start a bounded agent session using the normalized task request and policy context.
- Deliverable: working agent session starter
- Dependencies: 2.2
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: A direct session-start CLI exists at `node scripts/agent-control.js start-session --task-request <path>`, writes session records under `.agent-sdlc/state/agent-sessions/`, and performs runtime handoff into the worker container scaffold. File-backed task intake now supports optional `--auto-start-session`, enabling end-to-end manual event replay without requiring the webhook route. The session record includes runtime workspace and artifact references for later proposal and verification handoff.

### WBS 3.3 — Worker Runtime Scaffold
- Parent: 3
- Related Phase: Phase 1
- Description: Stand up the initial isolated workspace/runtime scaffold.
- Deliverable: working isolated runtime scaffold
- Dependencies: 2.3
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: The first repo-owned worker-runtime Dockerfile exists at `docker/worker-runtime/Dockerfile`, has been built locally as `agent-sdlc-worker-runtime:test`, and is exercised by `agent-control start-session` for a per-session runtime launch path. The runtime image and loopback Gitea host are now configurable through the Gitea bootstrap template/local config with environment overrides still available. The runtime now prepares a session-local workspace checkout plus runtime-launch artifacts under `.agent-sdlc/runtime/` that are consumed by the proposal path. The current runtime source path now clones the forge target repository and target branch into the worker workspace, with loopback local-Gitea URLs normalized to a container-reachable host so proposal branches inherit active workflow files from forge `main` during local validation.

### WBS 3.4 — PR Proposal Path
- Parent: 3
- Related Phase: Phase 1
- Description: Surface the agent's bounded change as a branch and PR or equivalent proposal with source-task linkage.
- Deliverable: working proposal path with task/session references
- Dependencies: 3.1, 3.2, 3.3
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: A working proposal path now exists at `node scripts/proposal-surface.js create-gitea-pr --session <path>`. The current slice reads the prepared session/task records, force-adds `.agent-sdlc/traceability/<task_request_id>.json` inside the prepared workspace, pushes `agent/<task_request_id>` to Gitea, and creates or updates the linked PR with the reviewer-facing traceability block. When the proposal PR already exists, the path now pre-seeds proposal traceability from the open PR before the branch update so the local Gitea path does not need a second amend-and-push just to backfill `proposal_ref`.

### WBS 3.5 — CI Verification Skeleton
- Parent: 3
- Related Phase: Phase 1
- Description: Independently validate the proposed change through CI and retain linkage to the proposal and originating task.
- Deliverable: working CI skeleton with proposal/task linkage
- Dependencies: 2.4, 3.4
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: The first PR-triggered CI workflow now exists at `.gitea/workflows/phase1-ci.yml`, and the repo-local runner helper now exists at `node scripts/dev/ensure-local-gitea-runner.js ensure-runner`. Runner container, image, label, network, and instance URL defaults now come from the Gitea bootstrap template/local config with environment overrides still available. The current workflow collects `.agent-sdlc/ci/verification-metadata.json` from the proposal branch, runs `npm ci`, `npm run validate:platform`, and `npm run typecheck`, and was smoke-tested successfully against the local Gitea stack with run `#19` completing successfully after the localhost-rooted topology was updated to use host networking plus an injected `agent-sdlc-gitea` host alias for runner-triggered job containers. After the runtime workspace source switched from local-workspace cloning to forge-repository cloning, a live PR `#5` revalidation also restored successful auto-created `pull_request_sync` runs and successful branch-local `workflow_dispatch` execution for the proposal branch. The same workflow now also posts CI completion back to the host review-surface listener through the local `host.docker.internal` callback path, which is documented as a committed workflow-local configuration exception and was validated on seeded PR `#23` with successful run `#41`. Uploaded artifact chunks now persist in local Gitea storage, while operator-facing artifact listing visibility remains a narrower follow-up. Proposal creation now includes a local-forge seed preflight that blocks branch updates when local forge `main` lags workspace `HEAD`, so stale workflow or CI scripts are caught before new PR runs.

### WBS 3.6 — Lifecycle Traceability Scaffold
- Parent: 3
- Related Phase: Phase 1
- Description: Implement the minimum record or metadata path that preserves traceability from event intake through human review.
- Deliverable: minimal end-to-end traceability scaffold
- Dependencies: 2.5, 3.2, 3.4, 3.5
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: The first proposal-linked traceability artifact exists. `proposal-surface create-gitea-pr` writes `.agent-sdlc/traceability/<task_request_id>.json` into the proposal branch and records `proposal_ref` / `proposal_url` back into the session record. CI now extends that linkage by generating `.agent-sdlc/ci/verification-metadata.json`, reviewer-visible job-log and step-summary metadata, a linked traceability artifact enriched with `ci_run_ref`, workflow metadata, and final verification status, and a refreshed PR traceability block that shows whether the proposal is ready for human review. `review-surface sync-gitea-pr-review-outcome` now completes the minimum Phase 1 traceability path by syncing Gitea review decisions back into the canonical root traceability record, mirroring updates into session-local copies, and refreshing the PR body with explicit review decision and reviewer metadata. The same surface now also resolves proposal-linked review follow-up from file-backed review events or a dedicated review webhook listener, and it now supports proposal-traceability sync for CI completion so canonical and session-local copies converge automatically after successful PR verification. The local bootstrap now starts that review listener, ensures the default local repo is wired to the matching callback, and the end-to-end CI-to-host convergence path was validated against seeded PR `#23` and run `#41`. CI finalize can now defer direct PR body refresh to host-side review-surface sync when the workflow checkout lacks ignored local Gitea credentials, preserving project-config source-of-truth without turning missing CI-local credentials into a false validation failure.

### WBS 3.7 — Testing Workflow Baseline
- Parent: 3
- Related Phase: Phase 1
- Description: Establish a repeatable local testing workflow with durable planning, case-definition, and current-state tracking surfaces for the Phase 1 closed loop.
- Deliverable: repo-owned local test plan, testing framework, active test dashboard, archive, and canonical CLI/GUI procedures
- Dependencies: 3.1, 3.2, 3.4, 3.5, 3.6
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: The repo now has a stable testing workflow baseline under `docs/testing/`, including `test-plan.md`, `test-framework.md`, `local-test-procedures.md`, `test-dashboard.md`, `test-archive.md`, and canonical case notes under `docs/testing/items/`. The current testing workflow defines repeatable CLI replay, CLI half-live, GUI full-live, and composite manual-acceptance procedures for the Phase 1 closed loop, tracks active near-term validation items separately from canonical cases, and records the default local Gitea credentials, repo name, URLs, evidence paths, and webhook-delivery debug surfaces needed for manual local verification. `docs/phase1-deliverable.md` and `TC-008` now package that workflow into a delivery-oriented manual acceptance path for the current P1 slice.

### WBS 3.8 — User Capability Matrix
- Parent: 3
- Related Phase: Phase 1
- Description: Maintain one durable user-facing matrix that explains where `@agent` is supported, what each supported task token means in current implementation terms, and how live versus manual workflow surfaces fit together.
- Deliverable: `docs/user-capability-matrix.md`
- Dependencies: 1.2, 3.1, 3.2, 3.4, 3.5, 3.6, 3.7
- Critical-Path-Candidate: No
- Status: Done
- Notes: The repo now has a dedicated user capability matrix at `docs/user-capability-matrix.md` that ties the project vision to the current Phase 1 implementation packaging. The document separates live `@agent` entrypoints, manual operator commands, unsupported surfaces, current lifecycle coverage, and durable evidence surfaces so future changes to intake, proposal, CI, or review flow can update one current-state document instead of relying on scattered issue notes or chat summaries.

### WBS 3.9 — Minimal Real Agent Execution
- Parent: 3
- Related Phase: Phase 1
- Description: Implement one real provider-backed agent execution path for a single supported task class so the Phase 1 loop includes bounded AI-generated repository changes instead of only classification, runtime preparation, and proposal scaffolding.
- Deliverable: one validated provider-backed execution path, expected to start with `bounded_code_change`, plus the supporting documentation and evidence needed to operate it repeatably
- Dependencies: 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8
- Critical-Path-Candidate: Yes
- Status: In Progress
- Notes: This item intentionally deepens one task class before broadening intake surfaces or task-token coverage. The goal is to keep the Phase 1 slice narrow while making `agent-run change proposal` mean real bounded agent work inside the isolated runtime. The currently selected direction is a repo-owned execution adapter that supports both remote and local backends through configuration, with `DeepSeek API` as the short-term remote default and a later local-backend path preserved behind the same API-oriented execution boundary. The first implementation slice now adds tracked `config/agent-execution.template.yaml`, ignored local `config/agent-execution.yaml` generation, a repo-owned `scripts/lib/agent-execution.js` adapter, and session-record evidence wiring from `agent-control`; provider execution is opt-in while the existing scaffold path remains stable without API credentials. Provider-enabled validation first passed for `bounded_code_change` with task request `trq-4faac7e2a74b`, session `ags-cd9d3e289f02`, and local PR `#24`, then expanded to `documentation_update`, `review_follow_up`, and `ci_failure_investigation` with task requests `trq-2de69af748b1`, `trq-2644a836e239`, and `trq-859264e0df7f` plus local PRs `#25`, `#26`, and `#27`. A same-day CI stability correction found that those proposals were based on stale local forge `main` content and produced failed runs (`#46`-`#49`) with `Finalize CI Traceability` 401 errors from an older workflow/script revision; the mitigation reseeded local forge `main`, added proposal preflight blocking when forge `main` lags workspace `HEAD`, and completed fresh post-fix revalidation across all enabled tokens with successful runs `#51`-`#54` (`PR #1`, `#30`, `#31`, `#32`). The adapter now also hardens provider response parsing by extracting the first valid JSON object from mixed output so sessions fail less often on provider formatting noise. The `ci_failure_investigation` path now enforces evidence-oriented edit guardrails under `docs/testing/` and `docs/examples/`. Completed zero-edit provider results now also stop before PR creation as visible no-op outcomes rather than silently creating traceability-only proposals. The current P1 packaging now also records a durable docs-vs-code comparison in `docs/phase1-deliverable.md`, which explicitly treats the external docs path as the steadier acceptance baseline and the external code path as valid but still more review-sensitive. A fresh 2026-04-29 docs-safe regression now keeps this item open: issue `#41` / comment `#193` -> task `trq-097cad6b8f77` -> session `ags-2736c300be71` -> PR `#42` -> commit `83acd236a04c1d59dbf109c964e389308b53a053` showed that `README.md` (`11606` bytes) exceeded the current `maxFileBytes: 8000` context cap, and the provider then returned a partial full-file rewrite that deleted the unseen tail of the document. WBS `3.9` therefore still needs a large-file docs-update guardrail before close-out.

### WBS 3.10 — External Target Repo Evaluation Baseline
- Parent: 3
- Related Phase: Phase 1
- Description: Establish at least one distinct non-platform target repo path so service evaluation does not rely only on self-targeted platform runs.
- Deliverable: target-repo baseline plus the repo/bootstrap/test wiring needed to evaluate agent behavior outside `agent-sdlc`
- Dependencies: 3.4, 3.5, 3.7, 3.8, 3.9
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: ADR-0009 requires the project to distinguish platform regression evidence from service-quality evidence. The first concrete slice now exists as `fixtures/targets/target-docs/`, a docs-only external target repo baseline with a minimal target-side CI integration kit and repo-local validation scripts. The platform repo now also exposes `npm run eval:targets`, `npm run eval:target-docs:provision`, and `npm run eval:target-docs:reset` so the fixture can be seeded into local Gitea as `eval/target-docs` without reusing `agent-sdlc` as the target under test. A same-day seeding fix now snapshots nested fixture directories before push, and the first valid bounded evaluation run is captured in `TC-006` through task `trq-f77d70ed7f92`, session `ags-7f12724630cc`, PR `#4`, and successful CI run `#56`. A second fixture family now also exists as `fixtures/targets/target-code-small/`, with matching `npm run eval:target-code-small:provision` and `npm run eval:target-code-small:reset` commands. The first valid bounded-code external-target evaluation is now captured in `TC-007` through task `trq-7d9a75db740f`, session `ags-b02a30c22316`, PR `#6`, and successful CI run `#59`, while the same case also records two earlier failed retries as useful behavior-quality evidence.

### WBS 3.11 — Service-State And Evaluation Workflow
- Parent: 3
- Related Phase: Phase 1
- Description: Make workbench/internal-eval state explicit and define the evidence model that separates platform self-test from broader service evaluation.
- Deliverable: durable service-state policy, evidence rules, and current-state doc alignment
- Dependencies: 3.7, 3.8, 3.10
- Critical-Path-Candidate: Yes
- Status: Done
- Notes: This item is about governance and current-state clarity, not only about new code. ADR-0009 plus `docs/policies/service-state-and-evaluation.md` now define the evidence rule that self-targeted `agent-sdlc` runs remain valid for bootstrap and regression but cannot by themselves justify pilot or production service claims. The first runnable external-target evidence set now exists, so the policy, testing workflow, and current-state docs are aligned to a real `Workbench` / `Internal Eval` evidence model instead of a purely planned one.

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

### WBS 4.4 — Pilot Promotion Gates
- Parent: 4
- Related Phase: Phase 2
- Description: Define and implement staged rollout controls that govern how task classes and target repos move from internal evaluation into pilot use.
- Deliverable: promotion-gate workflow for selected task classes, target repos, and user exposure
- Dependencies: 3.10, 3.11, 4.2, 4.3
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
| 3.7 | 3.1, 3.2, 3.4, 3.5, 3.6 | the testing workflow baseline depends on a real closed-loop path worth validating and observing |
| 3.8 | 1.2, 3.1, 3.2, 3.4, 3.5, 3.6, 3.7 | the capability matrix depends on both the planned user experience and the implemented lifecycle surfaces it describes |
| 3.9 | 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8 | the first real agent execution path depends on working session/runtime/proposal/verification handoffs plus current-state workflow and validation surfaces |
| 3.10 | 3.4, 3.5, 3.7, 3.8, 3.9 | credible service evaluation needs a working proposal/CI/testing baseline plus at least one real execution path before it can move beyond self-targeted platform runs |
| 3.11 | 3.7, 3.8, 3.10 | service-state and evidence rules depend on both the testing workflow and the introduction of a distinct target-repo evaluation baseline |
| 4 | 3 | expansion should follow first working loop |
| 4.4 | 3.10, 3.11, 4.2, 4.3 | staged pilot rollout depends on explicit evidence tiers plus policy and observability support |
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
- 3.7
- 3.8
- 3.9
- 3.10
- 3.11

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
- 2026-04-20: Updated WBS 3.3 and 3.5 after fixing runtime workspace sourcing to clone the forge target repo/branch, which restored proposal-branch workflow presence and live PR `#5` run creation in local Gitea.
- 2026-04-20: Updated WBS 3.4 after pre-seeding traceability for already-open PRs, reducing the local Gitea existing-PR refresh path to one new sync-triggered run.
- 2026-04-20: Updated WBS 3.6 after landing review-outcome synchronization from local Gitea PR reviews into the canonical traceability record and reviewer-facing PR body.
- 2026-04-21: Updated WBS 3.6 after adding proposal-based review sync plus review-event replay/webhook entrypoints for automation-ready review follow-up.
- 2026-04-21: Updated WBS 3.1 and 3.6 after wiring the default local bootstrap to start the managed issue-comment and review-follow-up listeners and to configure the default local repo hook set.
- 2026-04-21: Updated WBS 3.1 and 3.6 after adding the local Gitea webhook allowlist needed for host callback delivery and validating live PR close/reopen webhook sync into the bootstrap-managed review listener.
- 2026-04-21: Added WBS 3.7 for the durable local testing workflow baseline, including test plan, framework, dashboard, archive, and canonical CLI/GUI cases.
- 2026-04-22: Updated WBS 3.5 and 3.6 after landing the CI-to-host traceability callback path and validating automatic canonical/session-local convergence on seeded PR `#23`.
- 2026-04-22: Added WBS 3.8 for the durable user capability matrix that ties live `@agent` entrypoints to the current Phase 1 lifecycle.
- 2026-04-22: Added WBS 3.9 to make the first real provider-backed agent execution path an explicit Phase 1 work item instead of an implicit expectation.
- 2026-04-22: Narrowed WBS 3.9 toward a config-selected remote/local-capable execution adapter with `DeepSeek API` as the short-term remote default.
- 2026-04-23: Moved WBS 3.9 to in progress after adding the first config-selected agent execution adapter slice and session evidence wiring.
- 2026-04-23: Added ADR-0008-backed configuration template governance to WBS 1.4.
- 2026-04-23: Updated WBS 3 after moving local Gitea/dev bootstrap settings to the ADR-0008 template/local-config pattern.
- 2026-04-23: Updated WBS 3.1 after moving npm webhook listener startup to template/local bootstrap settings.
- 2026-04-23: Updated WBS 3.3 and 3.5 after moving runner and worker-runtime startup defaults to template/local bootstrap settings.
- 2026-04-23: Recorded provider-enabled WBS 3.9 validation through local PR `#24` and adjusted CI traceability sync so workflow checkouts can defer PR body refresh to the host-side review surface instead of requiring ignored local Gitea credentials in CI.
- 2026-04-23: Expanded WBS 3.9 provider-enabled coverage to `documentation_update`, `review_follow_up`, and `ci_failure_investigation` through local PRs `#25`-`#27`.
- 2026-04-23: Corrected local CI evidence for PRs `#25`-`#29` after identifying stale forge seeding as the instability root cause, and added proposal preflight protection so stale forge `main` is blocked before new proposal creation.
- 2026-04-23: Completed fresh post-fix WBS 3.9 multi-token revalidation with successful runs `#51`-`#54`, and hardened provider JSON extraction for mixed-output responses.
- 2026-04-24: Added WBS 3.10 and 3.11 to separate external target-repo service evaluation from self-targeted platform regression and to make service-state/evidence rules explicit before later pilot claims.
- 2026-04-24: Moved WBS 3.10 and 3.11 to in progress after adding the first `target-docs` external fixture, provisioning/reset command surface, and runnable `TC-006` baseline definition.
- 2026-04-24: Marked WBS 3.10 and 3.11 done after fixing nested-fixture seeding and collecting the first valid external-target evidence set on `eval/target-docs`.
- 2026-04-24: Expanded the WBS 3.10 note after adding the second fixture family `target-code-small` and its matching provision/reset command surface.
- 2026-04-24: Expanded WBS 3.7 and 3.9 notes after adding the P1 delivery-oriented acceptance pack and the durable docs-vs-code evidence comparison.
- 2026-04-29: Updated WBS 3.1 and 3.9 after landing bounded issue-thread feedback for malformed/fail-closed live issue-comment results and a no-op stop that avoids creating traceability-only PRs.
- 2026-04-29: Kept WBS `3` and `3.9` in progress after a fresh docs-safe run exposed a large-file truncation regression in the current agent-execution contract.
