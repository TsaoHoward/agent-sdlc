# I-001: Phase 1 Minimum Closed Loop Implementation

## Metadata
- Issue ID: I-001
- Status: Done
- Last Updated: 2026-04-30
- Owner: Project Maintainer
- Related Docs / WBS: `docs/roadmap.md` Phase 1; `docs/wbs.md` WBS `3`, `3.1`, `3.2`, `3.3`, `3.4`, `3.5`, `3.6`, `3.7`, `3.8`, `3.9`
- Source Dashboard: docs/issues/issue-dashboard.md
- Source Template: docs/templates/issue-note.template.md

## Summary
The project has completed its minimum closed-loop design baseline and now has the first executable Phase 1 slices for webhook intake, runtime handoff, proposal creation, PR-triggered CI verification, and explicit review-outcome synchronization. This note captures the remaining packaging gap so future runs can continue from the new review-linked traceability surface without rediscovering the same context.

That remaining packaging gap is now closed for Phase 1 baseline purposes: the last active blocker was the large-file `documentation_update` truncation regression, and the post-fix live rerun on issue `#41` / comment `#204` confirmed `trq-763eac216fe1` -> `ags-716c62e3f62c` -> `PR #44` -> run `#71` with safe `README.md` additions only.

## Why It Matters
The repository is intentionally still in an early-phase, structure-first posture. Without a durable packaging note, Phase 1 implementation can fragment into ad hoc coding or repeatedly restart from design review instead of moving through bounded implementation slices.

## Current State
- Phase 0 baseline items are complete, including roadmap, WBS, architecture, policy, environment baseline, and prompts.
- Phase 1 design items are complete, including task intake, runtime isolation, agent control integration, PR/CI path, and lifecycle traceability contracts.
- Machine-readable policy scaffolding exists under `config/policy/`.
- A project-local bootstrap entrypoint now exists to initialize `.agent-sdlc/` state paths and start the current local Gitea development forge from the repository, with repo-owned bootstrap settings, explicit high-port forwarding, PostgreSQL-backed startup as the default local path, SQLite as a fallback, and admin-password refresh behavior that preserves the tracked forced-password-change setting.
- A first bounded implementation slice now exists:
  - `node scripts/task-gateway.js normalize-gitea-issue-comment --event <path>` can parse the selected `@agent run <token>` contract against `config/policy/*.yaml`, persist normalized task requests under `.agent-sdlc/state/task-requests/`, and now optionally start an agent session automatically for manual event replay.
  - `node scripts/task-gateway.js serve-configured-gitea-webhook` can accept actual Gitea-compatible issue-comment webhook deliveries using template/local bootstrap settings, retain source-event evidence under `.agent-sdlc/state/source-events/`, and persist normalized task requests.
  - `node scripts/agent-control.js start-session --task-request <path>` now creates session records under `.agent-sdlc/state/agent-sessions/`, launches the worker-runtime container, and prepares runtime artifacts plus a session-local workspace under `.agent-sdlc/runtime/` for auto-approved task requests.
  - `node scripts/dev/ensure-local-gitea-repo.js ensure-local-repo --owner <owner> --repo <repo> --seed-from <path>` can provision the local Gitea owner/repository path used by the proposal-flow smoke tests and now seeds remote `main` from the source repo's current `HEAD` so the local forge sees the active workspace's tracked workflow files.
  - `node scripts/dev/ensure-local-gitea-runner.js ensure-runner` can provision the local Gitea Actions runner and place job containers on the shared Docker network used by the local forge.
  - `node scripts/proposal-surface.js create-gitea-pr --session <path>` now force-adds `.agent-sdlc/traceability/<task_request_id>.json` inside the prepared workspace, pushes `agent/<task_request_id>` to Gitea, and creates or updates the linked PR.
  - `.gitea/workflows/phase1-ci.yml` now runs on PR open/update/reopen, executes `npm ci`, `npm run validate:platform`, and `npm run typecheck`, writes verification linkage to `.agent-sdlc/ci/verification-metadata.json` plus the CI job log and step summary, enriches the traceability artifact with CI run references and final verification status, refreshes the PR traceability block with CI and review-readiness state, and uploads both verification metadata and traceability metadata as workflow artifacts even when verification fails.
  - the local Gitea smoke-test baseline now includes a successful PR-triggered workflow run against the local forge and runner path.
  - the current control-host implementation uses repo-local Node.js CLIs as the first slice on the selected platform-stack convergence path rather than as a new architecture boundary by itself.
- The platform stack is now selected in ADR-0006:
  - the platform core should converge on `TypeScript` / `Node.js LTS` with `npm`
  - repo-owned Dockerfiles should package the control-plane and worker runtime before later compose consolidation
  - PowerShell remains acceptable for local operator wrappers without becoming the main control-plane implementation language
- ADR-0006's first implementation slice now exists:
  - `package.json`, `package-lock.json`, and `tsconfig.json` define the npm-managed control-plane baseline
  - `npm run validate:platform` and `npm run typecheck` now verify the current platform package
  - `docker/worker-runtime/Dockerfile` and `docker/worker-runtime/entrypoint.sh` define the first worker-runtime image scaffold
  - the worker-runtime image scaffold has been built locally as `agent-sdlc-worker-runtime:test`
- The repo now has the first independent CI workflow plus an explicit review-outcome sync surface:
  - `node scripts/review-surface.js sync-gitea-pr-review-outcome --session <path>` reads the linked Gitea PR plus review state, updates the canonical `.agent-sdlc/traceability/<task_request_id>.json` record, mirrors that state back into the session-local traceability copy when present, and refreshes the reviewer-facing PR traceability block with review decision and reviewer identity metadata
  - the review-outcome sync path keeps the root traceability record as the canonical source so later syncs do not regress CI status or other already-finalized lifecycle metadata when a session-local workspace copy is stale
  - a live local validation against PR `#5` confirmed both the no-review state (`awaiting human review decision`) and a real local Gitea `APPROVED` review (`#1` by `howard`), which updated the PR body and traceability artifact to `approved by reviewer`
  - the same review-follow-up surface now also supports `--proposal`, file-backed Gitea review-event replay, and a dedicated webhook listener so review or PR-close events can resolve the linked proposal and sync all matching session-local traceability copies without a session-specific operator hop
  - the local bootstrap now starts both the task-gateway and review-follow-up webhook listeners by default and ensures the default local repo is wired to those callback URLs during repo bootstrap
- A fuller 2026-04-20 local test pass established two sharper facts:
  - the CI-linked reviewer-surface code path works end to end when exercised directly: a live manual `collect -> attach -> finalize` pass against PR `#5` updated `.agent-sdlc/traceability/trq-849dfc1cb4a7.json`, `.agent-sdlc/ci/verification-metadata.json`, and the PR body to `CI: success` plus `Review Status: ready for human review`
  - the missing-run / dispatch gap was rooted in proposal-branch contents rather than in a globally broken Gitea Actions trigger path: proposal branches for PR `#4` and `#5` did not contain `.gitea/workflows/phase1-ci.yml`, even though local forge `main` did
  - that missing workflow in the PR head explains both observed Gitea 1.25.5 symptoms: no auto-created PR runs for fresh proposal updates and `404 workflow doesn't exist` when dispatch targeted those proposal branches
  - `agent-control start-session` now prepares runtime workspaces by cloning the forge target repository and target branch instead of cloning the local workspace snapshot, and it rewrites loopback Gitea clone URLs to a container-reachable host for the worker runtime
  - a live re-run against PR `#5` with the new runtime source path restored `.gitea/workflows/phase1-ci.yml` to the proposal branch head, completed successful `pull_request_sync` runs `#21` and `#22`, and completed a successful branch-local `workflow_dispatch` run `#23` for `agent/trq-849dfc1cb4a7`
  - `proposal-surface create-gitea-pr` now pre-seeds traceability from an already-open PR before the branch update when the proposal already exists, so the existing-PR update path no longer needs a second amend-and-push just to backfill `proposal_ref`
  - a second live update against the same PR `#5` then increased the Actions run count from `23` to `24`, confirming that an existing-PR refresh now creates one `pull_request_sync` run instead of two
- The localhost-rooted local forge topology now uploads workflow artifacts successfully after the runner helper aligned runner and job-container networking with host loopback expectations and injected an `agent-sdlc-gitea` host alias for local job containers; local artifact listing visibility in Gitea remains a narrower follow-up if operator browsing becomes necessary.
- A 2026-04-21 local e2e pass against a fresh task request (`trq-8a0f9df00705`) and PR `#6` confirmed that the repo-owned commands can still carry a new task through session start, proposal creation, auto-created CI runs, successful `pull_request_sync` validation (`run #26`), and explicit reviewer approval sync into both PR body and durable traceability. That same pass also surfaced two narrower follow-ups:
  - `review-surface --proposal` needed to preserve CI state from local Gitea Actions runs when no canonical root traceability file existed yet, because otherwise a proposal-based review sync could regress the PR body from `CI: success` back to `CI: pending`
  - local Gitea webhook delivery to `host.docker.internal` callbacks was still blocked by the forge's default `webhook.ALLOWED_HOST_LIST`, so the bootstrap-managed listeners could be replayed directly but had not yet been reached by live forge deliveries
- A same-day bootstrap follow-up then traced the missing live review delivery to Gitea's webhook allowlist rather than to the listener path itself:
  - `hook_task` rows for the review hook showed `webhook can only call allowed HTTP servers` while dialing `host.docker.internal:4011`
  - the repo-owned bootstrap now sets `webhook.ALLOWED_HOST_LIST=external,private`, which admits the Docker-private callback address used by `host.docker.internal`
  - after restarting local Gitea with that setting, live PR `#6` close and reopen events created successful webhook deliveries in `hook_task`, refreshed `.agent-sdlc/traceability/trq-8a0f9df00705.json`, and updated the PR body through the bootstrap-managed review listener without manual replay
- A same-day testing workflow follow-up then promoted local validation into a durable repo-owned surface:
  - `docs/testing/test-plan.md` now defines the stable local test scope, environments, and default data
  - `docs/testing/test-framework.md` now defines replay, half-live, and full-live execution modes plus write-back rules
  - `docs/testing/local-test-procedures.md` now provides one operator-facing CLI and GUI walkthrough with concrete credentials, repo names, and observation points
  - `docs/testing/test-dashboard.md`, `docs/testing/test-archive.md`, and canonical case notes under `docs/testing/items/` now preserve the current regression workflow and the current GUI-path understanding without leaving that knowledge only in issue notes or chat
- A fresh 2026-04-21 GUI validation against issue `#7` then corrected that understanding:
  - the live issue comment created task request `trq-21b5684940ee`
  - the task gateway auto-started session `ags-923b5c3e7217`
  - the session reached `runtime_handoff_status: workspace-prepared`
  - no PR was created automatically from that live issue-comment path
  - the current reproducible boundary is therefore live intake plus session preparation, followed by a manual `proposal-surface create-gitea-pr --session <path>` step when the operator wants to continue into proposal, CI, and review follow-up
- A same-day strengthening pass then closed that GUI boundary and exposed the next narrower gap:
  - `agent-control start-session` now supports automatic proposal continuation for the live issue-comment path, and `proposal-surface create-gitea-pr` now mirrors proposal traceability into the repo-root `.agent-sdlc/traceability/` state path as well as the session workspace copy
  - after a full listener restart, a fresh live run on issue `#11` created task request `trq-bd85673302e7`, auto-started session `ags-335855297620`, auto-created PR `#12`, and wrote `.agent-sdlc/traceability/trq-bd85673302e7.json` without manual `proposal-surface` intervention
  - `ensure-local-gitea-runner ensure-runner` now treats an `offline` runner as rebuild-worthy after forge restarts, which restored queued CI runs for PR `#12`
  - the latest duplicate-CI analysis identified route 1 as the preferred cleanup path for new PR creation: stop amending and force-pushing the proposal branch a second time after PR creation, and let CI recover proposal context from the workflow event or branch lookup when the committed branch artifact still carries the pre-PR seed state
  - that route-1 cleanup is now implemented: `proposal-surface create-gitea-pr` updates the host/session traceability copies plus the local workspace copy after PR creation without rewriting the remote proposal branch, the CI traceability scripts now resolve missing `proposal_ref` details from the workflow event payload or a branch-to-PR lookup, and a fresh post-fix live validation after seeding commit `e97f0ba` into local forge `main` created PR `#18` with one successful `pull_request` run (`#37`) instead of an immediate second `pull_request_sync` run
  - a 2026-04-22 follow-up closed that remaining host-side traceability gap: `review-surface` now supports proposal-traceability sync for canonical and session-local copies, CI now posts a host callback after finalize through the local `host.docker.internal` callback path, and a fresh seeded validation on PR `#23` completed one successful `pull_request` run (`#41`) with automatic convergence across the PR body, `.agent-sdlc/traceability/trq-route1-hostsync-final-20260421225724.json`, and the session-local workspace copy
- A 2026-04-23 provider-enabled validation pass then proved the first DeepSeek-backed execution slice through the session/proposal path:
  - local ignored `config/agent-execution.yaml` supplied `agentExecution.enabled: true` and `agentExecution.apiKey`
  - task request `trq-4faac7e2a74b` started session `ags-cd9d3e289f02`
  - DeepSeek generated `docs/examples/provider-live-smoke.md` in the session workspace and requested `npm run validate:platform`, which passed
  - `agent-control --auto-create-proposal` created local Gitea PR `#24`
  - local Actions run `#42` proved that repository validation passed but exposed a CI traceability regression: workflow checkout did not have ignored local Gitea credentials, so direct PR body PATCH returned 401 after validation had already succeeded
  - the fix keeps project config as source of truth by allowing CI finalize to record deferred PR body sync instead of failing validation, while host-side `review-surface` sync refreshes the PR body using the control host's ignored project config
  - revalidation run `#45` then completed successfully on PR `#24` with the reviewer-facing PR body automatically converged to `CI: success` / `ready for human review`
  - a same-day follow-up expanded provider-enabled coverage to `documentation_update`: task request `trq-2de69af748b1` started session `ags-0e18b7db5b88`, generated `docs/examples/provider-docs-smoke.md`, and created local PR `#25`
  - provider-enabled coverage has now expanded to the remaining two issue-comment task tokens: `review_follow_up` created task request `trq-2644a836e239`, session `ags-94e3f03d2f6b`, and local PR `#26`; `ci_failure_investigation` created task request `trq-859264e0df7f`, session `ags-c742088383aa`, and local PR `#27`
  - the `ci_failure_investigation` adapter path now enforces docs-scoped investigation outputs (`docs/testing/` and `docs/examples/`) so the investigation profile remains evidence-oriented during provider execution
- A same-day CI stability correction then updated that evidence:
  - recent local runs `#46`-`#49` actually failed at `Finalize CI Traceability` with `401 PATCH /pulls/*`
  - the root cause was stale local forge `main` content (`316f89a`) that proposal branches inherited for PRs `#25`-`#29`
  - local forge `main` was reseeded from current workspace `HEAD`
  - `proposal-surface create-gitea-pr` now performs a preflight check and fails fast with a reseed command when local forge `main` lags workspace `HEAD`
- A same-day post-fix revalidation then reconfirmed the provider-enabled path:
  - fresh runs covered all enabled tokens with task requests `trq-c9b2fa3064fb`, `trq-8dc2bbe48812`, `trq-fd8ca8f8d18f`, and `trq-7765e00f85d4`
  - sessions `ags-33be3cb8741c`, `ags-b8311df3ef0c`, `ags-9f4217fcbdc7`, and `ags-327998def612` produced proposals `PR #1`, `#30`, `#31`, and `#32`
  - local Actions runs `#51`-`#54` all completed successfully, with traceability converging to `ci_status: success`, `ready-for-human-review`, and `proposal_body_sync_status: synced`
  - provider response handling now extracts the first valid JSON object from mixed output to reduce session failures from provider formatting noise
- A next-day governance follow-up then made the branch expectation explicit:
  - `docs/policies/branch-and-local-forge-sync.md` now records the Phase 1 rule that proposal content must come from the forge target branch and that the default local seeded repo must be reseeded before proposal or CI validation when workspace `HEAD` has advanced
  - the same rule is now linked from README, environment bootstrap guidance, and the PR/CI path document so stale forge `main` is treated as a governed workflow hazard rather than only a troubleshooting detail
- A same-day packaging follow-up then turned the current state into a delivery-oriented handoff:
  - `docs/phase1-deliverable.md` now summarizes what Phase 1 currently delivers, what remains out of scope, and how the current docs-oriented versus bounded-code evidence should be interpreted
  - the new comparison explicitly treats `eval/target-docs` as the steadier first manual acceptance checkpoint and `eval/target-code-small` as the stricter bounded-code quality gate because the code fixture kept two earlier failed retries before the passing narrowed run
  - `docs/testing/items/TC-008-phase1-manual-deliver-acceptance.md` now defines a step-by-step manual acceptance path that chains the existing canonical cases instead of requiring operators to reconstruct the intended order from multiple notes
- A 2026-04-24 fresh manual acceptance walkthrough then revalidated that packaging in practice:
  - the walkthrough completed with the explicit label `accepted for current P1 manual confirmation`
  - the platform replay/proposal/live GUI slices all passed again, including issue `#33` / comment `#166` -> task `trq-08c59229d0a9` -> session `ags-e52b3bc208c0` -> `PR #34` -> UI run `#56`
  - the external docs rerun passed on `eval/target-docs` through task `trq-530938b564d7`, session `ags-cf7e0c1b0033`, `PR #6`, and UI run `#3`
  - the external bounded-code rerun first failed closed because the `summary:` payload exceeded the 280-character intake limit, then passed on the shortened retry through task `trq-7f9ab84dbce5`, session `ags-f90ba2a103be`, `PR #8`, and UI run `#4`
  - a concise Traditional Chinese operator guide now also exists at `docs/user-guide.zh-TW.md` so the current P1 slice can be explained without requiring every reader to start from the full capability matrix

## Dependencies And Constraints
- Work should stay aligned to Phase 1 and WBS 3 rather than pulling Phase 2 observability or multi-source scope forward.
- Implementation should preserve the existing layer boundaries between task gateway, policy, agent control, runtime, CI, and deploy.
- New architecture or governance shifts discovered during implementation should be escalated through the decision backlog and ADR flow rather than buried in code.
- Environment dependencies do not all need to be packaged inside the repository yet, but the active development stack should remain startable from repository-owned entrypoints so later consolidation into `docker compose` or an equivalent launcher stays possible.

## Proposed Handling Or Work Packaging
1. Start with the smallest intake-and-state slice:
   define the normalized task-request persistence path under `.agent-sdlc/state/task-requests/` and the trigger-adapter scaffold that can parse the selected issue-comment command contract.
2. Add the direct session-start boundary:
   implement the `agent-control start-session --task-request <path>` entry point and the file-backed session record under `.agent-sdlc/state/agent-sessions/`.
3. Stand up the isolated worker scaffold:
   prepare the ephemeral container runner interface and session-local workspace initialization needed by the runtime boundary.
4. Add proposal surfacing:
   implement branch naming, PR body traceability block, and `.agent-sdlc/traceability/<task_request_id>.json` creation.
5. Attach CI and lifecycle linkage:
   create the PR-triggered CI skeleton and carry `task_request_id` / proposal references through proposal and verification surfaces.

Steps 1 through 5 now have working implementation slices, with WBS 3.1 reaching a real trigger path, WBS 3.2/3.3 handing off into the worker image scaffold, WBS 3.4 creating a real Gitea proposal path, and WBS 3.5 exercising a real PR-triggered workflow on the local Gitea Actions path. The next packaging boundary is therefore narrower:
- land one minimal real provider-backed agent execution slice for a supported task class before broadening intake surfaces or token-specific workflows
- use a repo-owned API-oriented execution adapter that can switch between remote and local backends through configuration rather than hard-coding one provider into workflow orchestration
- apply ADR-0008 for future configurable modules so templates are checked in and operator-local config is generated and ignored when values vary by environment
- use `DeepSeek API` as the short-term remote default for that first execution slice while preserving a later local-backend path
- keep the current control-plane growth path inside the npm-managed package baseline
- keep the local forge seed path aligned to the active workspace `HEAD` so workflow and platform files match the code under test
- keep runtime workspace preparation sourced from the forge target repository and target branch so proposal heads inherit active workflow files and other forge-truth content
- keep the current explicit review-outcome and proposal-traceability sync surfaces aligned with the traceability contract
- keep the landed route-1 duplicate-CI cleanup in place so new PR creation does not reintroduce a second proposal-branch writeback
- keep the new testing workflow baseline aligned with the active command surface, local credentials, and evidence paths as the Phase 1 closed loop evolves
- treat the now-resolved PR-trigger / branch-dispatch gap as a content-source problem unless a narrower follow-up repro shows a remaining forge-level trigger defect
- investigate local artifact listing visibility only if operator-facing browsing of stored workflow artifacts becomes a near-term requirement
- do that without collapsing task gateway, agent control, worker, forge proposal, and CI responsibilities together

## Exit Path
This issue exits the active dashboard when the first implementation slice is underway and the remaining implementation work has either:
- been split into more focused active issue items, or
- been sufficiently reflected in WBS and implementation scaffolding that this packaging note is no longer the primary handoff surface.

If implementation uncovers a major unresolved decision, the issue should stay active until the decision is captured in `docs/decisions/decision-backlog.md` and, if needed, promoted to an ADR.

## Next Actions
- rerun and maintain the canonical CLI and GUI procedures under `docs/testing/` when intake, runtime, proposal, CI, review, or bootstrap behavior changes
- continue hardening the minimal provider-backed agent execution path from the validated `bounded_code_change`, `documentation_update`, `review_follow_up`, and `ci_failure_investigation` DeepSeek session/proposal smokes
- keep the newly validated opt-in DeepSeek adapter path bounded and repeatable when real credentials are enabled in ignored project config
- keep `docs/user-capability-matrix.md` aligned with the actual supported `@agent` locations, task tokens, and manual operator surfaces as the implementation evolves
- keep `docs/user-guide.zh-TW.md` aligned with the simpler operator-facing explanation of the same current-state boundaries
- keep the strengthened live issue-comment path in place now that it auto-creates the proposal and root traceability file
- keep the CI-to-host traceability callback path stable so `.agent-sdlc/traceability/<task_request_id>.json` continues to converge automatically after CI success
- keep the route-1 duplicate-CI cleanup covered by future local PR-creation validation so new proposal-path changes do not reintroduce an immediate second CI run
- keep the forge-repository runtime clone path in place and reseed local forge `main` from current `HEAD` before local proposal-flow validation when the operator is testing unpushed changes
- use `docs/phase1-deliverable.md` and `TC-008` as the default near-term manual confirmation package instead of relying on scattered dashboard references
- use the current docs-vs-code comparison to decide whether bounded-code follow-up should focus on prompt narrowing, rubric tightening, or both
- investigate local artifact listing visibility only if operator-facing browsing of stored workflow artifacts becomes necessary
- expand the current project-local bootstrap entrypoints as those WBS 3 interfaces become real services or commands
- split or reframe this dashboard item once the implementation slices are concrete enough to track separately

## Change Log
- 2026-04-15: Initial version.
- 2026-04-15: Marked the issue in progress after adding the initial project-local environment bootstrap scaffold.
- 2026-04-15: Expanded the local forge bootstrap scaffold to include a PostgreSQL-backed default path and Docker Desktop auto-start handling.
- 2026-04-16: Updated the issue after validating successful localhost-topology workflow artifact upload in local Gitea run `#19`.
- 2026-04-15: Added repo-owned bootstrap config and non-interactive local Gitea installation behavior.
- 2026-04-15: Verified the local bootstrap against a clean Gitea/PostgreSQL data set with automated admin-user creation and sign-in-page readiness.
- 2026-04-15: Captured the bootstrap fix that reapplies the tracked admin `mustChangePassword` setting during password refresh for existing data sets.
- 2026-04-15: Recorded the first working task-intake normalization and pending session-start CLI scaffolds for WBS 3.1 and 3.2.
- 2026-04-15: Added the selected platform-stack and packaging baseline after promoting it to ADR-0006.
- 2026-04-15: Recorded the npm-managed control-plane baseline and first locally built worker-runtime Dockerfile scaffold.
- 2026-04-15: Recorded webhook-backed task intake, retained source-event evidence, and per-session runtime handoff into the worker image scaffold.
- 2026-04-16: Recorded the local Gitea repo helper, first working branch/PR proposal path, and proposal-linked traceability artifact.
- 2026-04-16: Recorded the local Gitea Actions runner helper, first PR-triggered CI workflow, and verification-metadata linkage path.
- 2026-04-20: Recorded the local repo seed-path fix to push current `HEAD` into forge `main`, the live manual PR `#5` CI-finalization validation, and the remaining missing-actions-run trigger gap for fresh local PR events.
- 2026-04-20: Recorded the local Gitea 1.25.5 workflow-dispatch `404 workflow doesn't exist` behavior for the active `phase1-ci.yml` workflow.
- 2026-04-20: Recorded the root cause of the missing PR runs and proposal-branch dispatch `404` as proposal heads missing `.gitea/workflows/phase1-ci.yml`, then verified the forge-clone runtime fix with successful runs `#21`, `#22`, and `#23` against PR `#5`.
- 2026-04-20: Recorded the existing-PR proposal update optimization that pre-seeds traceability from the already-open PR and verified it by reducing a fresh PR `#5` refresh to one new `pull_request_sync` run (`#24`).
- 2026-04-20: Recorded the new review-outcome sync surface, the canonical root-traceability writeback rule, and the live local Gitea approval validation that updated PR `#5` to `approved by reviewer`.
- 2026-04-21: Recorded the automation-ready review-follow-up expansion after adding proposal-based sync, review-event replay, and a dedicated review webhook listener.
- 2026-04-21: Recorded the default-bootstrap integration that now starts both managed webhook listeners and ensures the default local repo hook set points at those control-host callbacks.
- 2026-04-21: Recorded the fresh PR `#6` e2e validation pass, the CI-preservation fix in proposal-based review sync, and the follow-up gap that local Gitea host callbacks still needed webhook-allowlist support.
- 2026-04-21: Recorded the local Gitea webhook-allowlist fix and the successful live PR `#6` close/reopen deliveries that reached the bootstrap-managed review listener automatically.
- 2026-04-21: Recorded the repo-owned testing workflow baseline, including the test plan, framework, canonical case notes, active test dashboard, and archive for the Phase 1 regression workflow.
- 2026-04-21: Reframed the testing follow-up after the same-day local e2e pass confirmed the full live issue-comment path and moved that proof into the durable testing workflow.
- 2026-04-21: Corrected the GUI-path understanding after a fresh run on issue `#7` showed that live issue-comment handling currently stops at `workspace-prepared` and still needs manual proposal continuation.
- 2026-04-21: Recorded the strengthened live issue-comment path on issue `#11`, the automatic proposal/root-traceability restoration, the runner offline-recovery fix after forge restart, and the remaining host-side canonical traceability convergence gap after CI success.
- 2026-04-21: Added the preferred duplicate-CI cleanup route: remove the new-PR second amend/push in proposal creation instead of solving the duplicate only at the CI layer.
- 2026-04-21: Landed the route-1 duplicate-CI cleanup, added CI-side proposal-context fallback for pre-PR traceability seeds, and validated the new path with synthetic local PR `#15`, which produced only one queued `pull_request` run (`#35`).
- 2026-04-21: Revalidated the landed route-1 duplicate-CI cleanup after seeding commit `e97f0ba` into local forge `main`; fresh PR `#18` completed one successful `pull_request` run (`#37`) and reaffirmed that the remaining gap is host-side canonical traceability refresh after CI success.
- 2026-04-22: Closed the remaining host-side canonical traceability refresh gap by adding proposal-traceability sync plus a CI host callback, then validated automatic convergence on seeded local PR `#23` with successful run `#41`.
- 2026-04-22: Added `docs/user-capability-matrix.md` as the durable current-state handoff for supported `@agent` entrypoints, task tokens, manual operator surfaces, and lifecycle coverage.
- 2026-04-22: Added the explicit packaging follow-up to land one real provider-backed agent execution slice in Phase 1, with `bounded_code_change` as the preferred first target.
- 2026-04-22: Narrowed the first real execution slice toward a config-selected remote/local-capable adapter with `DeepSeek API` as the short-term remote default.
- 2026-04-23: Recorded the first implementation slice for `config/agent-execution.template.yaml`, local generated `config/agent-execution.yaml`, `scripts/lib/agent-execution.js`, and session-record execution evidence.
- 2026-04-23: Recorded the repository-wide configuration template policy from ADR-0008.
- 2026-04-23: Recorded provider-enabled DeepSeek validation through session `ags-cd9d3e289f02` and local PR `#24`, plus the CI traceability adjustment that defers PR body refresh to host-side sync when CI checkout lacks ignored local Gitea credentials.
- 2026-04-23: Expanded provider-enabled DeepSeek coverage to `documentation_update`, `review_follow_up`, and `ci_failure_investigation` through local PRs `#25`-`#27`.
- 2026-04-23: Corrected local CI evidence for PRs `#25`-`#29` after identifying stale forge seeding as the `Finalize CI Traceability` 401 root cause in runs `#46`-`#49`, then reseeded forge `main` and added proposal preflight guardrails.
- 2026-04-23: Recorded fresh post-fix provider revalidation across all enabled tokens with successful CI runs `#51`-`#54`, and captured provider JSON extraction hardening for mixed-output responses.
- 2026-04-24: Added the formal branch/local-forge synchronization policy and linked it back into Phase 1 proposal and bootstrap guidance.
- 2026-04-24: Added the delivery-oriented Phase 1 packaging note, the docs-vs-code comparison, and the new `TC-008` manual acceptance handoff.
- 2026-04-29: Wrote back the fresh `TC-008` acceptance walkthrough and linked the new concise Traditional Chinese operator guide into the Phase 1 packaging context.
