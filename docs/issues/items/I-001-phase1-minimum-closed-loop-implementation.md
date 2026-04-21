# I-001: Phase 1 Minimum Closed Loop Implementation

## Metadata
- Issue ID: I-001
- Status: In Progress
- Last Updated: 2026-04-21
- Owner: Project Maintainer
- Related Docs / WBS: `docs/roadmap.md` Phase 1; `docs/wbs.md` WBS `3`, `3.1`, `3.2`, `3.3`, `3.4`, `3.5`, `3.6`, `3.7`
- Source Dashboard: docs/issues/issue-dashboard.md
- Source Template: docs/templates/issue-note.template.md

## Summary
The project has completed its minimum closed-loop design baseline and now has the first executable Phase 1 slices for webhook intake, runtime handoff, proposal creation, PR-triggered CI verification, and explicit review-outcome synchronization. This note captures the remaining packaging gap so future runs can continue from the new review-linked traceability surface without rediscovering the same context.

## Why It Matters
The repository is intentionally still in an early-phase, structure-first posture. Without a durable packaging note, Phase 1 implementation can fragment into ad hoc coding or repeatedly restart from design review instead of moving through bounded implementation slices.

## Current State
- Phase 0 baseline items are complete, including roadmap, WBS, architecture, policy, environment baseline, and prompts.
- Phase 1 design items are complete, including task intake, runtime isolation, agent control integration, PR/CI path, and lifecycle traceability contracts.
- Machine-readable policy scaffolding exists under `config/policy/`.
- A project-local bootstrap entrypoint now exists to initialize `.agent-sdlc/` state paths and start the current local Gitea development forge from the repository, with repo-owned bootstrap settings, explicit high-port forwarding, PostgreSQL-backed startup as the default local path, SQLite as a fallback, and admin-password refresh behavior that preserves the tracked forced-password-change setting.
- A first bounded implementation slice now exists:
  - `node scripts/task-gateway.js normalize-gitea-issue-comment --event <path>` can parse the selected `@agent run <token>` contract against `config/policy/*.yaml`, persist normalized task requests under `.agent-sdlc/state/task-requests/`, and now optionally start an agent session automatically for manual event replay.
  - `node scripts/task-gateway.js serve-gitea-webhook --host 127.0.0.1 --port 4010 --route /hooks/gitea/issue-comment` can accept actual Gitea-compatible issue-comment webhook deliveries, retain source-event evidence under `.agent-sdlc/state/source-events/`, and persist normalized task requests.
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
  - the remaining narrower gap is now host-side canonical traceability convergence after CI success: the PR body updates to the successful run automatically, but the host root traceability file can still lag until a later host-side sync event such as review follow-up or manual proposal-based review refresh
  - the latest duplicate-CI analysis identified route 1 as the preferred cleanup path for new PR creation: stop amending and force-pushing the proposal branch a second time after PR creation, and let CI recover proposal context from the workflow event or branch lookup when the committed branch artifact still carries the pre-PR seed state
  - that route-1 cleanup is now implemented: `proposal-surface create-gitea-pr` updates the host/session traceability copies plus the local workspace copy after PR creation without rewriting the remote proposal branch, the CI traceability scripts now resolve missing `proposal_ref` details from the workflow event payload or a branch-to-PR lookup, and a fresh local synthetic validation created PR `#15` with only one queued `pull_request` run (`#35`) instead of an immediate second `pull_request_sync` run

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
- keep the current control-plane growth path inside the npm-managed package baseline
- keep the local forge seed path aligned to the active workspace `HEAD` so workflow and platform files match the code under test
- keep runtime workspace preparation sourced from the forge target repository and target branch so proposal heads inherit active workflow files and other forge-truth content
- keep the current explicit review-outcome sync surface aligned with the traceability contract and close the remaining host-side canonical traceability convergence gap after CI success
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
- keep the strengthened live issue-comment path in place now that it auto-creates the proposal and root traceability file
- close the remaining host-side canonical traceability sync gap so `.agent-sdlc/traceability/<task_request_id>.json` converges automatically after CI success without waiting for a later host-side sync event
- keep the route-1 duplicate-CI cleanup covered by future local PR-creation validation so new proposal-path changes do not reintroduce an immediate second CI run
- keep the forge-repository runtime clone path in place and reseed local forge `main` from current `HEAD` before local proposal-flow validation when the operator is testing unpushed changes
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
