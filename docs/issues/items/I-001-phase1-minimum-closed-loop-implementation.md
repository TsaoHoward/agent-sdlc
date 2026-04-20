# I-001: Phase 1 Minimum Closed Loop Implementation

## Metadata
- Issue ID: I-001
- Status: In Progress
- Last Updated: 2026-04-20
- Owner: Project Maintainer
- Related Docs / WBS: `docs/roadmap.md` Phase 1; `docs/wbs.md` WBS `3`, `3.1`, `3.2`, `3.3`, `3.4`, `3.5`, `3.6`
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
- A fuller 2026-04-20 local test pass established two sharper facts:
  - the CI-linked reviewer-surface code path works end to end when exercised directly: a live manual `collect -> attach -> finalize` pass against PR `#5` updated `.agent-sdlc/traceability/trq-849dfc1cb4a7.json`, `.agent-sdlc/ci/verification-metadata.json`, and the PR body to `CI: success` plus `Review Status: ready for human review`
  - the missing-run / dispatch gap was rooted in proposal-branch contents rather than in a globally broken Gitea Actions trigger path: proposal branches for PR `#4` and `#5` did not contain `.gitea/workflows/phase1-ci.yml`, even though local forge `main` did
  - that missing workflow in the PR head explains both observed Gitea 1.25.5 symptoms: no auto-created PR runs for fresh proposal updates and `404 workflow doesn't exist` when dispatch targeted those proposal branches
  - `agent-control start-session` now prepares runtime workspaces by cloning the forge target repository and target branch instead of cloning the local workspace snapshot, and it rewrites loopback Gitea clone URLs to a container-reachable host for the worker runtime
  - a live re-run against PR `#5` with the new runtime source path restored `.gitea/workflows/phase1-ci.yml` to the proposal branch head, completed successful `pull_request_sync` runs `#21` and `#22`, and completed a successful branch-local `workflow_dispatch` run `#23` for `agent/trq-849dfc1cb4a7`
  - `proposal-surface create-gitea-pr` now pre-seeds traceability from an already-open PR before the branch update when the proposal already exists, so the existing-PR update path no longer needs a second amend-and-push just to backfill `proposal_ref`
  - a second live update against the same PR `#5` then increased the Actions run count from `23` to `24`, confirming that an existing-PR refresh now creates one `pull_request_sync` run instead of two
- The localhost-rooted local forge topology now uploads workflow artifacts successfully after the runner helper aligned runner and job-container networking with host loopback expectations and injected an `agent-sdlc-gitea` host alias for local job containers; local artifact listing visibility in Gitea remains a narrower follow-up if operator browsing becomes necessary.

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
- keep the current explicit review-outcome sync surface aligned with the traceability contract and decide later whether that sync should remain operator-invoked or move into an automated follow-up surface
- treat the now-resolved PR-trigger / branch-dispatch gap as a content-source problem unless a narrower follow-up repro shows a remaining forge-level trigger defect
- investigate local artifact listing visibility only if operator-facing browsing of stored workflow artifacts becomes a near-term requirement
- do that without collapsing task gateway, agent control, worker, forge proposal, and CI responsibilities together

## Exit Path
This issue exits the active dashboard when the first implementation slice is underway and the remaining implementation work has either:
- been split into more focused active issue items, or
- been sufficiently reflected in WBS and implementation scaffolding that this packaging note is no longer the primary handoff surface.

If implementation uncovers a major unresolved decision, the issue should stay active until the decision is captured in `docs/decisions/decision-backlog.md` and, if needed, promoted to an ADR.

## Next Actions
- decide whether `review-surface sync-gitea-pr-review-outcome` should remain an operator-invoked Phase 1 command or move into a later automated review-follow-up path
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
