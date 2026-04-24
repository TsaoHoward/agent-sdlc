# Issue Dashboard

## Document Metadata
- Version: 0.1
- Status: Active
- Last Updated: 2026-04-24
- Owner: Project Maintainer
- Source Template: docs/templates/issue-dashboard.template.md

## Purpose
This document is the durable dashboard for active near-term project issues that deserve repository-level visibility.

It does not replace forge issues, roadmap/WBS planning structure, the decision backlog, or ADRs. It is the current-state and handoff surface for meaningful project issues that would otherwise drift into chat or scattered notes.

## Issue Classification
- include only active or near-term issues that materially affect execution, coordination, blockers, or cross-run handoff
- keep complex issue detail in supporting notes under `docs/issues/items/`
- do not mirror every forge issue, comment thread, or small implementation task here

## Status Model
- `Open`
- `In Progress`
- `Blocked`
- `Ready For Review`
- `Deferred`
- `Done`
- `Closed`

## Move-Out Rule
- keep only active or near-term items in this document
- move `Done` or `Closed` items out at the next document maintenance pass
- move `Deferred` items out when they are no longer near-term
- record moved-out items in `docs/issues/issue-archive.md` when a lightweight history entry is still useful

## Supporting-Note Rule
- create a supporting issue note under `docs/issues/items/` when background, dependency, evidence, or handoff context no longer fits cleanly in the dashboard
- keep the dashboard concise even when a supporting note exists

## Exit And Promotion Rule
- every active issue item should record its intended exit path
- update roadmap and WBS when an issue changes work structure, scope, sequencing, or dependencies
- update `docs/decisions/decision-backlog.md` when an issue reveals a major unresolved decision
- create or update an ADR when an issue changes architecture, source-of-truth ownership, or cross-cutting governance

## Dashboard
| Issue ID | Title | Status | Related Docs / WBS | Next Action | Exit Path |
|---|---|---|---|---|---|
| I-001 | Phase 1 Minimum Closed Loop Implementation Packaging | In Progress | `docs/roadmap.md` Phase 1; WBS `3`, `3.1`-`3.9` | Continue hardening the provider-enabled agent execution path, keep the testing workflow and user capability matrix current, preserve the CI-to-host traceability callback path, enforce the new forge-seed preflight in proposal creation, and improve operator-facing artifact browsing | Archive after the first slice is underway and the remaining work is split or absorbed into active execution tracking |
| I-002 | Configuration Template Policy Compliance Gaps | Done | ADR-0008; `docs/policies/configuration-management.md`; WBS `3.1`, `3.3`, `3.5`, `3.9` | Move out of the active dashboard at the next issue-maintenance pass if no new config-template gap appears | Archive after the current completion no longer needs active dashboard visibility |

## Issue Items

### I-001 - Phase 1 Minimum Closed Loop Implementation Packaging
- Status: `In Progress`
- Related Docs / WBS: `docs/roadmap.md` Phase 1; `docs/wbs.md` WBS `3`, `3.1`, `3.2`, `3.3`, `3.4`, `3.5`, `3.6`, `3.7`, `3.8`, `3.9`
- Why It Matters: The repository has completed the planning and design baseline for the first closed loop, but the implementation path still needs durable packaging into executable slices so work can leave the planning-only state.
- Current State: Task-intake, policy, runtime, PR/CI, and traceability contracts are documented, and `config/policy/` scaffolding exists. The repo now also has a project-local environment bootstrap entrypoint plus a repo-owned Gitea bootstrap config that uses explicit high-port forwarding and non-interactive PostgreSQL-backed forge initialization by default, and the bootstrap password-refresh path now preserves the tracked admin `mustChangePassword` setting so manual sign-in does not fall into an unstable forced password-change flow. The current implementation slice now includes a webhook-backed task gateway that retains source-event evidence under `.agent-sdlc/state/source-events/`, writes normalized task requests under `.agent-sdlc/state/task-requests/`, and auto-starts the direct session starter for auto-approved issue-comment commands. ADR-0006 has now been applied to the repo in four concrete ways: an npm-managed control-plane baseline exists via `package.json`, `package-lock.json`, and `tsconfig.json`; the first worker-runtime Dockerfile exists at `docker/worker-runtime/Dockerfile` and has been built locally as `agent-sdlc-worker-runtime:test`; `agent-control start-session` now launches that image to prepare a per-session workspace and runtime artifacts under `.agent-sdlc/runtime/`; `proposal-surface create-gitea-pr` now turns that prepared workspace into a real Gitea branch/PR proposal while writing the first linked traceability artifact into the proposal branch; and the first PR-triggered CI workflow now runs on the local Gitea Actions stack, generating verification linkage in `.agent-sdlc/ci/verification-metadata.json`, job logs, step summaries, a refreshed PR traceability block with CI run and review-readiness status, and a persisted artifact in the local forge storage path after validation run `#19`. During the 2026-04-20 fuller local test pass, `ensure-local-gitea-repo --seed-from .` was corrected to seed remote `main` from the source repo's current `HEAD`, which restored workflow files in the local forge and allowed a live manual `collect -> attach -> finalize` validation path against PR `#5`; that pass confirmed the traceability artifact, verification metadata, and reviewer-facing PR block all update correctly to `success` / `ready for human review`. The same day's follow-up trigger investigation has now resolved the missing-run / dispatch gap: proposal branches for PR `#4` and `#5` were being prepared from the local workspace snapshot instead of the forge target repository, so those branch heads did not contain `.gitea/workflows/phase1-ci.yml` even though local forge `main` did. That missing workflow in the PR head explained both observed Gitea 1.25.5 symptoms: no auto-created PR runs and `404 workflow doesn't exist` for branch-local dispatch. `agent-control start-session` now prepares runtime workspaces by cloning the forge target repository and target branch instead, while translating loopback Gitea URLs to a container-reachable host for the worker runtime. A live re-run against PR `#5` then restored branch-local workflow availability, completed successful `pull_request_sync` runs `#21` and `#22`, and completed a successful branch-local `workflow_dispatch` run `#23` for `agent/trq-849dfc1cb4a7`. The traceability path now also reaches explicit review outcomes: `review-surface sync-gitea-pr-review-outcome` reads Gitea PR review state from the canonical root traceability artifact, mirrors the update into session-local traceability copies, refreshes the PR body, and was validated against a live local Gitea `APPROVED` review (`#1`) on PR `#5`, which updated the reviewer-facing surface to `approved by reviewer`. That review-follow-up surface now also accepts file-backed Gitea review events plus a dedicated webhook route, letting proposal-linked review or PR-close events refresh durable traceability without requiring a session-specific manual command. The default local bootstrap now starts both managed webhook listeners, ensures the default local repo carries the matching issue-comment plus review-follow-up webhook set, and now also sets `webhook.ALLOWED_HOST_LIST=external,private` so Gitea can actually deliver those host callback URLs from inside the forge container. A live PR `#6` close/reopen validation then confirmed successful review-follow-up webhook deliveries in `hook_task`, plus automatic traceability and PR-body refresh through the bootstrap-managed listener. A strengthened 2026-04-21 local GUI validation on `howard/agent-sdlc#11` then restored the user-facing issue-comment path: the live issue comment created task request `trq-bd85673302e7`, auto-started session `ags-335855297620`, auto-created PR `#12`, and wrote `.agent-sdlc/traceability/trq-bd85673302e7.json` without manual `proposal-surface` intervention. A same-day runner recovery fix also restored queued runs after forge restart by treating `offline` runner state as rebuild-worthy in `ensure-local-gitea-runner`. The route-1 duplicate-CI cleanup has now landed in the proposal path: new-PR creation no longer amends and force-pushes a second proposal-branch commit just to backfill `proposal_ref`, CI traceability scripts now resolve proposal context from the workflow event or branch lookup when the committed branch artifact still carries the pre-PR seed state, and a fresh post-fix live validation created PR `#18` with one successful `pull_request` run (`#37`) instead of the earlier immediate second `pull_request_sync` run. A 2026-04-22 follow-up then closed the remaining host-side canonical traceability convergence gap: `review-surface` now supports proposal-traceability sync for canonical and session-local copies, CI now posts a host callback after finalize using the local callback topology, and a fresh seeded validation on PR `#23` completed one successful `pull_request` run (`#41`) with automatic convergence across the PR body, host root traceability file, and session-local workspace copy. The first WBS `3.9` implementation slice now uses tracked `config/agent-execution.template.yaml`, generated ignored `config/agent-execution.yaml`, and `scripts/lib/agent-execution.js`, wires session-record evidence from `agent-control`, and keeps provider calls disabled by default so existing no-key local paths stay stable. Provider-enabled validation has now passed through task request `trq-4faac7e2a74b`, session `ags-cd9d3e289f02`, and local PR `#24`, where DeepSeek generated `docs/examples/provider-live-smoke.md` and requested `npm run validate:platform`, which passed inside the session. That run exposed and fixed a CI traceability regression caused by workflow checkout lacking ignored local Gitea credentials: CI finalize now records deferred PR body sync instead of failing validation, and host-side review-surface sync refreshes the PR body from project-local config. Coverage has now expanded across all currently enabled tokens: `documentation_update` (`trq-2de69af748b1` -> `PR #25` -> run `#46`), `review_follow_up` (`trq-2644a836e239` -> `PR #26` -> run `#47`), and `ci_failure_investigation` (`trq-859264e0df7f` -> `PR #27` -> run `#48`). The investigation path now enforces docs-scoped evidence output under `docs/testing/` and `docs/examples/`.
- Current Correction (2026-04-23): recent local Actions runs `#46`-`#49` failed at `Finalize CI Traceability` with `401 PATCH /pulls/*`, and the root cause was stale local forge `main` content (`316f89a`) that still carried an older finalize script on proposal branches. Local forge `main` has been reseeded to current workspace `HEAD`, and proposal creation now fails fast with an explicit reseed instruction when local forge `main` lags workspace `HEAD`.
- Post-Fix Revalidation (2026-04-23): fresh provider-enabled runs now pass across all enabled tokens with `PR #1`/`#30`/`#31`/`#32` and local CI runs `#51`-`#54`; provider JSON extraction is also hardened to tolerate mixed-output wrappers.
- Governance Follow-Up (2026-04-24): the repo now records the branch/local-forge synchronization rule in `docs/policies/branch-and-local-forge-sync.md` so stale seeded-forge content is treated as a governed workflow risk rather than only a testing note.
- Next Action: Continue hardening the provider-enabled DeepSeek path from the validated session/proposal smoke, keep maintaining the testing workflow under `docs/testing/`, keep `docs/user-capability-matrix.md` aligned with the actual supported `@agent` and operator workflow, preserve the CI-to-host traceability callback path during future proposal/CI changes, and improve operator-facing artifact browsing.
- Exit Path: Move this item to `docs/issues/issue-archive.md` once the first implementation slice is underway and the remaining work has been split into active execution issues or otherwise reflected in updated planning docs.
- Supporting Notes: `docs/issues/items/I-001-phase1-minimum-closed-loop-implementation.md`
- Promotion / Escalation Check: Update `docs/decisions/decision-backlog.md` and ADRs only if implementation uncovers a new major boundary, ownership, or governance decision.
- Notes: This item seeds the issue workflow with the project's current highest-signal active issue after the Phase 0 and Phase 1 design baseline.

### I-002 - Configuration Template Policy Compliance Gaps
- Status: `Done`
- Related Docs / WBS: ADR-0008; `docs/policies/configuration-management.md`; `docs/roadmap.md` Phase 1; `docs/wbs.md` WBS `3.1`, `3.3`, `3.5`, `3.9`
- Why It Matters: ADR-0008 makes checked-in templates plus ignored local config the repository-wide policy for configurable modules. The first compliant module exists, but several current startup surfaces still expose operator-controlled values through tracked realized config, package-script arguments, workflow env, env-only defaults, or code constants.
- Current State: `config/agent-execution.template.yaml` plus ignored `config/agent-execution.yaml` is compliant. Machine-readable policy under `config/policy/` remains committed source-of-truth policy input and is documented as an explicit exception category. The local Gitea/dev bootstrap now follows the ADR-0008 pattern with tracked `config/dev/gitea-bootstrap.template.json`, ignored generated `config/dev/gitea-bootstrap.json`, and `npm run dev:gitea-bootstrap-config`. The npm task-gateway and review-surface webhook entrypoints, local Gitea runner defaults, and worker-runtime launch defaults now resolve from that template/local bootstrap config; explicit CLI flags and environment overrides remain available for manual override. The CI-to-host traceability callback is documented as a committed workflow-local configuration exception in `docs/policies/configuration-management.md`, and CI PR body refresh now defers to host-side review-surface sync when the workflow checkout lacks ignored local Gitea credentials.
- Next Action: Move out of the active dashboard at the next issue-maintenance pass if no new config-template gap appears.
- Exit Path: Archive after this completion no longer needs active dashboard visibility.
- Supporting Notes: `docs/issues/items/I-002-configuration-template-policy-compliance-gaps.md`
- Promotion / Escalation Check: Update ADR-0008 or create a new ADR only if remediation changes source-of-truth ownership, secret-handling expectations, runtime isolation, CI ownership, or governance rules.
- Notes: This issue was created from the 2026-04-23 policy compliance audit after `agent-execution` established the first repository-owned template/local-config implementation.

## Change Log
- 2026-04-15: Initial version.
- 2026-04-15: Seeded I-001 to track the current Phase 1 implementation packaging gap.
- 2026-04-15: Marked I-001 in progress after adding the initial project-local environment bootstrap scaffold.
- 2026-04-15: Updated I-001 to reflect repo-owned bootstrap config, explicit forwarded ports, and non-interactive local Gitea installation.
- 2026-04-15: Recorded the admin-password refresh fix that keeps manual Gitea sign-in from re-entering the forced password-change flow.
- 2026-04-15: Updated I-001 after landing the first task-intake normalization and file-backed session-start scaffolds.
- 2026-04-15: Updated I-001 after selecting the platform implementation-stack and packaging baseline in ADR-0006.
- 2026-04-15: Updated I-001 after implementing the npm-managed control-plane baseline and the first worker-runtime Dockerfile scaffold.
- 2026-04-15: Updated I-001 after landing webhook-backed task intake, retained source-event records, and per-session worker-runtime handoff.
- 2026-04-16: Updated I-001 after landing the first branch/PR proposal path and proposal-linked traceability artifact.
- 2026-04-16: Updated I-001 after landing the first PR-triggered CI workflow, local Gitea runner helper, and verification-metadata linkage.
- 2026-04-20: Updated I-001 after a fuller local closed-loop test fixed local repo seeding from current `HEAD`, manually validated CI finalization against PR `#5`, and narrowed the remaining blocker to missing auto-created actions runs for fresh PR events.
- 2026-04-20: Recorded that the local Gitea 1.25.5 workflow-dispatch endpoint also returned `404 workflow doesn't exist` for the active `phase1-ci.yml` workflow, keeping real run creation blocked at the forge-trigger layer.
- 2026-04-20: Recorded the root cause of the missing PR runs and branch-dispatch `404` as proposal branches missing `.gitea/workflows/phase1-ci.yml`, then verified the forge-clone runtime fix by observing successful runs `#21`, `#22`, and `#23` for PR `#5`.
- 2026-04-20: Recorded the new review-outcome sync surface after validating a live local Gitea approval on PR `#5`, which now updates both durable traceability copies and the PR body with explicit reviewer decision metadata.
- 2026-04-21: Recorded the automation-ready review-follow-up expansion after adding proposal-based review sync, review-event replay, and a dedicated review webhook entrypoint.
- 2026-04-21: Recorded that the default local bootstrap now starts both managed webhook listeners and ensures the default local repo is wired to the matching issue-comment and review-follow-up callbacks.
- 2026-04-21: Recorded the local e2e validation pass for PR `#6`, including successful task-to-PR-to-CI flow, the CI-preservation fix in proposal-based review sync, and the follow-up gap that local Gitea host callbacks still needed webhook-allowlist support.
- 2026-04-21: Recorded the local Gitea webhook-allowlist fix and the successful live PR close/reopen deliveries that reached the bootstrap-managed review listener and refreshed durable traceability automatically.
- 2026-04-21: Recorded the repo-owned testing workflow baseline, including the new testing plan, framework, canonical case notes, and active test dashboard.
- 2026-04-21: Reframed the testing follow-up after the same-day local e2e pass confirmed the full live GUI path and moved that proof into the durable testing workflow and archive.
- 2026-04-21: Reopened the GUI issue-comment follow-up after a fresh validation on issue `#7` showed that the current default path still stops at `workspace-prepared` and requires manual proposal continuation.
- 2026-04-21: Recorded the strengthened live issue-comment path on issue `#11` and PR `#12`, plus the runner offline-recovery fix after forge restart, and narrowed the remaining gap to host-side canonical traceability convergence after CI success.
- 2026-04-21: Added the preferred duplicate-CI follow-up route to I-001: remove the second amend/push from new-PR creation so CI no longer needs to absorb proposal-surface writeback churn.
- 2026-04-21: Recorded the landed route-1 duplicate-CI cleanup plus a fresh local PR `#15` validation that produced only one queued `pull_request` run (`#35`) instead of an immediate sync-triggered second run.
- 2026-04-21: Revalidated the landed duplicate-CI cleanup after seeding commit `e97f0ba` into local forge `main`; fresh PR `#18` completed one successful `pull_request` run (`#37`), while the host-side canonical traceability refresh gap remained.
- 2026-04-22: Recorded the host-side canonical traceability convergence fix after seeded local PR `#23` completed one successful `pull_request` run (`#41`) and automatically updated the PR body, root traceability file, and session-local workspace copy.
- 2026-04-22: Added the durable user capability matrix and linked I-001 to its ongoing maintenance as part of the Phase 1 packaging surface.
- 2026-04-22: Added the explicit Phase 1 follow-up to land one real provider-backed agent execution slice instead of treating AI execution as an implied scaffold outcome.
- 2026-04-22: Narrowed the remaining WBS `3.9` implementation direction to a config-selected remote/local-capable execution adapter with `DeepSeek API` as the short-term remote default.
- 2026-04-23: Recorded the first WBS 3.9 implementation slice for the config-selected agent execution adapter and session evidence wiring.
- 2026-04-23: Recorded ADR-0008 as the repository-wide policy for checked-in config templates and ignored local config.
- 2026-04-23: Added I-002 to track configuration-template policy compliance gaps across local bootstrap, webhook, runner, worker-runtime, and CI callback startup settings.
- 2026-04-23: Marked I-002 in progress after moving local Gitea/dev bootstrap to a tracked template plus ignored generated local config.
- 2026-04-23: Updated I-002 after moving npm control-host webhook listener startup to template/local bootstrap settings.
- 2026-04-23: Updated I-002 after moving local runner and worker-runtime defaults to template/local bootstrap settings.
- 2026-04-23: Marked I-002 done after documenting the CI workflow callback URL as an explicit workflow-local configuration exception.
- 2026-04-23: Recorded provider-enabled DeepSeek validation for WBS 3.9 and the CI traceability fix that keeps ignored local Gitea credentials out of workflow checkout while preserving host-side PR body sync.
- 2026-04-23: Expanded provider-enabled WBS 3.9 coverage to `documentation_update`, `review_follow_up`, and `ci_failure_investigation` through local PRs `#25`-`#27`.
- 2026-04-23: Corrected local CI evidence for PRs `#25`-`#29` after confirming stale forge seeding caused `Finalize CI Traceability` 401 failures in runs `#46`-`#49`; reseeded local forge `main` and added proposal preflight guardrails.
- 2026-04-23: Recorded fresh post-fix provider revalidation across all enabled tokens with successful local CI runs `#51`-`#54`, and added provider JSON extraction hardening evidence to I-001.
- 2026-04-24: Added the formal branch/local-forge synchronization policy and linked it back into the active Phase 1 issue context.
