# Issue Dashboard

## Document Metadata
- Version: 0.1
- Status: Active
- Last Updated: 2026-11-08
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
| #3 | Add safe, repeatable version upgrades for the existing Docker Gitea | In Progress | `docs/issues/items/I-007-gitea-version-lifecycle-operations.md`; WBS `3.12`; TC-011 | Run current PR #6 head on native Windows PowerShell 5.1 and isolated Docker Desktop; complete the AC-16 fault matrix before considering implementation accepted. Keep formal 43000 operations and #29 separately authorized | Move to archive after implementation review and authorized Windows Host acceptance; keep any unresolved runtime blocker linked from the canonical test case |

## Issue Items
### #3 — Gitea Version Lifecycle Operations
- Status: `In Progress`
- Related Docs / WBS: `docs/issues/items/I-007-gitea-version-lifecycle-operations.md`; WBS `3.12`; `docs/testing/items/TC-011-gitea-version-lifecycle-operations.md`
- Why It Matters: The existing legacy Gitea instance has persistent repositories, Actions, Registry, and shared Runner state. Replacing its image without a verified backup and restore path risks making that state unusable.
- Current State: The accepted implementation contract separates legacy Docker Gitea on port 43000 from Compose port 46300. Upgrade remains explicit-version, backup-first, local-only, and live maintenance remains separately authorized. The current PR adds schema-2 manifest checks, schema-3 write-ahead recovery state, immutable attempt records, same-Backup-ID Restore retry, pure-read status/list, guarded command behavior, effective local-storage coverage checks, and real Docker/Git/Actions/ORAS/host-Runner E2E procedures. It adds native argv and no-anonymous-volume checks plus adjacent-hop Restore consumers. No current-head PowerShell or Docker Desktop tests have run.
- Current Finding: Original-source closeout now fails closed once target create/start may have begun and verifies the bootstrap image pin. The E2E includes a real Docker rename conflict before target creation, a post-create network detach, and a fresh-process Marker reload. AC-16 still lacks the complete U0–U9/R0–R9/C1–C2 pre/post interruption matrix. `npm run validate:platform` passed; typecheck could not start without `node_modules/typescript`, Pester could not start because `powershell` is absent, and Docker Desktop context `info` failed with `protocol not available`. Earlier Pester results apply only to older commits. No formal Gitea service or data was operated.
- Next Action: Run current PR #6 on native Windows PowerShell 5.1 with isolated Docker Desktop, complete the remaining AC-16 injections, record the AC-01–AC-16 matrix, and review the PR. Keep Issue #3 open for any unpassed implementation gates and separately authorized 43000/#29 acceptance.
- Exit Path: Archive after implementation and authorized Windows Host acceptance are complete; record any remaining issue as a separate follow-up.
- Supporting Note: `docs/issues/items/I-007-gitea-version-lifecycle-operations.md`
- Promotion Check: WBS `3.12` added; no architecture boundary or source-of-truth change is intended, so no ADR is required.

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
- 2026-04-24: Added I-003 to track the new ADR-0009 requirement to separate platform self-test evidence from external target-repo service-evaluation evidence.
- 2026-04-24: Moved I-003 to in progress after landing the first `target-docs` external fixture and local provisioning/reset command surface.
- 2026-04-24: Marked I-003 done after fixing nested-fixture seeding and collecting the first valid external-target evidence set on `eval/target-docs`.
- 2026-04-24: Added I-004 to track the second external-target fixture family for the first bounded-code evaluation baseline.
- 2026-04-24: Marked I-004 done after `TC-007` captured the first valid bounded-code external-target evidence on `eval/target-code-small`.
- 2026-04-24: Reframed I-001 around the new P1 delivery-oriented acceptance pack and docs-vs-code comparison.
- 2026-04-29: Updated I-001 after the fresh `TC-008` manual walkthrough was written back and a concise Traditional Chinese user guide was added alongside the capability matrix.
- 2026-04-29: Added I-005 to keep the next issue-comment feedback and no-op UX design follow-up in durable issue tracking after landing the minimal bounded P1 fix.
- 2026-04-29: Applied the current Phase 1 close interpretation to I-001 and I-005, treating deterministic no-op coverage and bounded-code hardening as deferred follow-up and adding the DFD output mechanism as a tracked UX/diagnostic design need.
- 2026-04-29: Added I-006 after a fresh provider-backed docs-safe run on `README.md` exposed a large-file truncation regression in the current agent-execution contract.
- 2026-04-30: Moved I-006 to ready-for-review after landing fail-closed guardrails plus safe fragment-edit support for truncated large files and verifying both behaviors through deterministic local stubbed execution.
- 2026-04-30: Cleared the last active Phase 1 issue blockers after live rerun evidence (`#41` / comment `#204` -> `trq-763eac216fe1` -> `ags-716c62e3f62c` -> `PR #44` -> run `#71`) confirmed safe large-file docs updates, and moved completed or no-longer-near-term items to the issue archive.
- 2026-11-05: Added issue #3 as active near-term work and linked it to new WBS `3.12` and TC-011.
- 2026-11-05: Updated issue #3 handoff to track mocked Pester checks and outstanding isolated Windows Docker validation separately from live acceptance.
- 2026-11-05: Recorded the isolated Docker E2E harness, version-path correction, and the remaining Windows Host execution requirement.
- 2026-11-05: Updated issue #3 handoff with the valid post-start failure path, exact target-database restore checks, and current WSL validation limits.
- 2026-11-06: Recorded Windows Pester 6.2.0 Docker E2E failures and the Run-phase fixture/module setup plus verified-cleanup fix; post-fix E2E remains pending.
- 2026-11-06: Recorded stage/subcommand and credential-redacted stderr diagnostics; post-fix Windows Docker E2E remains pending.
- 2026-11-06: Recorded the Windows 23/23 Pester and fixture setup report plus the Actions preflight failure; switched to the documented paginated instance-wide admin-run API and left post-fix Windows Pester/E2E pending.
- 2026-11-06: Recorded Windows Pester 33/33, real NTFS ACL 1/1, and Docker E2E failure at the 268-character Git Object copy target; added extended-length file operations and a real-NTFS long-path regression, with post-patch Windows validation pending.
- 2026-11-06: Recorded the Windows 34/34 Pester and 1/1 long-path results and the subsequent Docker E2E byte-total/cleanup failures; added Hashtable summation, explicit prerequisite skips, and verified extended-path fixture cleanup. Post-fix Windows rerun remains pending.
- 2026-11-06: Recorded the Windows PowerShell/.NET Framework `File.Replace` null-backup root cause, the named-backup fix, and the focused real-NTFS bootstrap-pin verification still pending on the native checkout.
- 2026-11-06: Recorded focused bootstrap-pin Pester 5/5 and combined non-Docker Pester 43/44; full native-host Pester and post-fix isolated Docker E2E remain outstanding.
- 2026-11-06: Native Windows focused pin 5/5, full Pester 44/44, and GUID-isolated Docker E2E 3/3 passed; test fixture safely removed. Live 43000 acceptance remains pending; Issue #3 remains open.
- 2026-11-08: Added the Run #95 `completed` response compatibility follow-up; formal Gitea lifecycle operations remain separate and have not been performed.
- 2026-11-08: Recorded the RepoDigest concatenation root cause, pre-stop validation, operator-attested no-restore Recovery Marker reconciliation, Pester 55/55 excluding WSL interop ACL, and Docker Desktop E2E preflight block; formal services and marker remain untouched.
- 2026-11-08: Limited reconciliation compatibility to the exact schema-1 form with two official refs and one same-SHA `gitea/gitea` alias; Restore still rejects it. Added exact-shape Pester and isolated E2E coverage with the real topology validator; updated-head native reruns remain pending per maintainer direction.
- 2026-11-10: Added fail-closed validation of effective Gitea storage backends and local payload paths to Upgrade, Restore, and recovery closeout; added local/external/path coverage cases. Native PowerShell and Docker Desktop execution remain pending.
