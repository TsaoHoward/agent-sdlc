# Test Dashboard

## Document Metadata
- Version: 0.1
- Status: Active
- Last Updated: 2026-04-24
- Owner: Project Maintainer
- Source Template: docs/templates/test-dashboard.template.md

## Purpose
This document is the durable dashboard for active near-term local testing work that still deserves operator attention.

It does not replace CI run history, forge issue or PR history, roadmap/WBS planning structure, the issue dashboard, or ADRs. It is the current-state and handoff surface for meaningful testing work that would otherwise drift into chat or shell history.

## Test Classification
- include only active or near-term testing work that materially affects validation, coordination, or cross-run handoff
- keep detailed procedures in canonical case notes under `docs/testing/items/`
- do not mirror every single workflow run, PR review, or shell transcript here

## Status Model
- `Draft`
- `Ready`
- `In Progress`
- `Blocked`
- `Passed`
- `Failed`
- `Deferred`
- `Retired`

## Move-Out Rule
- keep only active or near-term items in this document
- move `Passed` or `Retired` items out at the next maintenance pass when they no longer need dashboard visibility
- move `Deferred` items out when they are no longer near-term
- record moved-out items in `docs/testing/test-archive.md` when a lightweight history entry is still useful

## Canonical-Case Rule
- keep exact CLI and GUI procedures in `docs/testing/items/`
- keep the dashboard concise even when a canonical case note exists

## Dashboard
| Test ID | Title | Status | Mode | Related Docs / WBS | Next Action | Exit Path |
|---|---|---|---|---|---|---|
| TC-001 | CLI Replay Intake And Session Smoke | Ready | CLI replay | `docs/roadmap.md` Phase 1; WBS `3.1`, `3.2`, `3.3` | Re-run when intake or session-start behavior changes and keep the case note current if task/session fields or evidence paths move | Move out after the current validation window once the case no longer needs active dashboard attention; keep the canonical case note as the long-lived procedure |
| TC-002 | CLI Proposal And Traceability Smoke | Passed | CLI half-live | `docs/roadmap.md` Phase 1; WBS `3.4`, `3.5`, `3.6` | Re-run when proposal, CI, or traceability wiring changes so the host callback and convergence path stay covered | Move out at the next maintenance pass if no new proposal/traceability regression appears |
| TC-004 | Agent Execution Adapter Smoke | Passed | CLI replay | `docs/roadmap.md` Phase 1; WBS `3.9` | Re-run when adapter parsing, provider config, allowed task classes, or path guardrails change | Move out at the next maintenance pass if no new provider-enabled regression appears |
| TC-005 | Real AI Connectivity Manual Flow | Passed | CLI half-live | `docs/roadmap.md` Phase 1; WBS `3.7`, `3.9` | Re-run when operator runbook steps, provider config, or token coverage changes | Move out at the next maintenance pass if no new operator-facing manual-flow gap appears |
| TC-006 | External Target Service-Evaluation Baseline | Passed | External target evaluation | ADR-0009; `docs/roadmap.md` Phase 1; WBS `3.10`, `3.11` | Move out at the next maintenance pass if no immediate follow-up remains beyond additional fixture expansion | Move out after the first external target-repo procedure is live and the current dashboard no longer needs to carry the baseline setup work |
| TC-007 | External Target Bounded-Code Evaluation Baseline | Passed | External target evaluation | `docs/roadmap.md` Phase 1; WBS `3.10`, `3.11` | Move out at the next maintenance pass unless immediate follow-up is needed on bounded-code prompt quality | Move out after the first bounded-code external-target run is captured and written back into the canonical case note |

## Test Items

### TC-001 - CLI Replay Intake And Session Smoke
- Status: `Ready`
- Mode: `CLI replay`
- Related Docs / WBS: `docs/testing/items/TC-001-cli-replay-intake-and-session-smoke.md`; WBS `3.1`, `3.2`, `3.3`
- Why It Matters: This is the fastest deterministic way to inspect task normalization and session-start boundaries without waiting on the live forge path.
- Current State: The current CLI replay path exists and is used as the first troubleshooting layer when live webhook validation is not necessary.
- Evidence Class: `platform self-test / platform regression`
- Next Action: Keep the procedure aligned with the current command surface and evidence paths under `.agent-sdlc/state/` and `.agent-sdlc/runtime/`.
- Exit Path: Move out after the current validation window when the dashboard no longer needs to carry it directly.
- Canonical Case: `docs/testing/items/TC-001-cli-replay-intake-and-session-smoke.md`
- Escalation Check: Update issue or decision surfaces if replay expectations change because of a new lifecycle or policy boundary.
- Notes: This case intentionally avoids depending on live Gitea delivery so it can stay as the first-line diagnostic.

### TC-002 - CLI Proposal And Traceability Smoke
- Status: `Passed`
- Mode: `CLI half-live`
- Related Docs / WBS: `docs/testing/items/TC-002-cli-proposal-and-traceability-smoke.md`; WBS `3.4`, `3.5`, `3.6`
- Why It Matters: This is the most direct way to validate proposal creation, traceability write-back, and direct review-sync entrypoints against the local forge.
- Current State: Proposal creation, reviewer-facing PR-body CI updates, and host-side traceability convergence are all working. A fresh seeded validation on synthetic proposal `PR #23` completed one successful `pull_request` run (`#41`) without the earlier duplicate sync-triggered second run, and the PR body, host root traceability file, and session-local workspace copy all converged automatically through the normal CI path.
- Evidence Class: `platform self-test / platform regression`
- Next Action: Re-run against future proposal-path changes so duplicate-CI and host-traceability regressions are caught early.
- Exit Path: Move out at the next maintenance pass if no new proposal, CI, or traceability regression reopens this path.
- Canonical Case: `docs/testing/items/TC-002-cli-proposal-and-traceability-smoke.md`
- Escalation Check: Open or update an issue when proposal, CI, or traceability linkage breaks in a way that blocks the Phase 1 closed loop.
- Notes: This case keeps the forge real while still letting the operator advance the lifecycle one command at a time.

### TC-004 - Agent Execution Adapter Smoke
- Status: `Passed`
- Mode: `CLI replay`
- Related Docs / WBS: `docs/testing/items/TC-004-agent-execution-adapter-smoke.md`; WBS `3.9`
- Why It Matters: This is the first validation surface for the new config-selected agent execution adapter before it is trusted as part of the live issue-to-PR path.
- Current State: The disabled-by-default adapter path has been smoke-tested without API credentials, and provider-enabled DeepSeek validation is now revalidated across all enabled task classes with fresh post-fix evidence: `bounded_code_change` (`trq-c9b2fa3064fb` -> `PR #1` -> run `#51`), `documentation_update` (`trq-8dc2bbe48812` -> `PR #30` -> run `#52`), `review_follow_up` (`trq-fd8ca8f8d18f` -> `PR #31` -> run `#53`), and `ci_failure_investigation` (`trq-7765e00f85d4` -> `PR #32` -> run `#54`). Proposal preflight now blocks stale forge-seed proposal creation, and agent execution parsing now tolerates non-clean provider JSON wrappers so sessions do not fail on otherwise valid payloads.
- Evidence Class: `platform self-test / platform regression`
- Next Action: Re-run when agent execution adapter behavior, provider config, allowed task classes, session evidence fields, or CI-to-host traceability sync changes.
- Exit Path: Move out at the next maintenance pass if no new provider-enabled regression appears.
- Canonical Case: `docs/testing/items/TC-004-agent-execution-adapter-smoke.md`
- Escalation Check: Update the decision backlog or ADRs only if provider validation shows the adapter must move orchestration, runtime, traceability, or policy ownership out of the current repo-owned boundaries.
- Notes: This case intentionally separates config/evidence validation from full live GUI validation so WBS `3.9` can harden without destabilizing the already-working closed loop.

### TC-005 - Real AI Connectivity Manual Flow
- Status: `Passed`
- Mode: `CLI half-live`
- Related Docs / WBS: `docs/testing/items/TC-005-real-ai-connectivity-manual-flow.md`; WBS `3.7`, `3.9`
- Why It Matters: Operators need one practical runbook that proves real provider connectivity with project config, real API key wiring, task/session evidence, proposal creation, and CI convergence.
- Current State: The manual-flow runbook is now revalidated across all currently enabled tokens on fresh proposals after reseed/preflight rollout: `@agent run code` (`trq-c9b2fa3064fb` -> `PR #1` -> run `#51`), `@agent run docs` (`trq-8dc2bbe48812` -> `PR #30` -> run `#52`), `@agent run review` (`trq-fd8ca8f8d18f` -> `PR #31` -> run `#53`), and `@agent run ci` (`trq-7765e00f85d4` -> `PR #32` -> run `#54`). All four traceability files converge to `ci_status: success`, `review.status: ready-for-human-review`, and `proposal_body_sync_status: synced`.
- Evidence Class: `platform self-test / platform regression`
- Next Action: Keep the runbook synchronized with current command surfaces, config fields, and latest reproducible evidence IDs.
- Exit Path: Move out at the next maintenance pass if no operator-facing real-AI connectivity follow-up remains.
- Canonical Case: `docs/testing/items/TC-005-real-ai-connectivity-manual-flow.md`
- Escalation Check: Open or update issue/decision surfaces when manual connectivity steps reveal drift between repo policy, local config, and runtime behavior.
- Notes: This case complements `TC-004` by emphasizing operator workflow and evidence collection instead of adapter internals only.

### TC-006 - External Target Service-Evaluation Baseline
- Status: `Passed`
- Mode: `External target evaluation`
- Related Docs / WBS: `docs/testing/items/TC-006-external-target-service-evaluation-baseline.md`; WBS `3.10`, `3.11`
- Why It Matters: The project now has a durable rule that self-targeted platform runs are useful but not sufficient for broader service-quality claims. This case is the first step toward evidence from a non-platform target repo.
- Current State: The first controlled external-target baseline now exists as `fixtures/targets/target-docs/`, with repo-local provisioning/reset commands and a minimal target-side CI integration kit. A post-fix live docs evaluation now passes on `eval/target-docs`: issue `#3` / comment `#153` -> task `trq-f77d70ed7f92` -> session `ags-7f12724630cc` -> PR `#4` -> run `#56` (`success`). The resulting change stayed bounded to `README.md` and `docs/faq.md`, and host-side traceability converged to `review.status=ready-for-human-review` with `proposal_body_sync_status=synced`.
- Next Action: Move this bootstrap case out at the next maintenance pass unless a near-term second fixture or external-target regression keeps it active.
- Exit Path: Move out after the first external target-repo procedure is runnable and the current dashboard no longer needs to carry the bootstrap/setup work directly.
- Canonical Case: `docs/testing/items/TC-006-external-target-service-evaluation-baseline.md`
- Escalation Check: Update issue, roadmap, WBS, or ADR surfaces if the first external target-repo path reveals a new environment, source-of-truth, or service-boundary assumption.
- Notes: This case is intentionally about service-evaluation credibility rather than only about more local smoke coverage. The first fixture stays docs-only on purpose so the repo boundary changes without also widening task risk at the same time. A same-day nested-fixture seeding bug was fixed before the passed evidence set was recorded.

### TC-007 - External Target Bounded-Code Evaluation Baseline
- Status: `Passed`
- Mode: `External target evaluation`
- Related Docs / WBS: `docs/testing/items/TC-007-external-target-bounded-code-evaluation-baseline.md`; WBS `3.10`, `3.11`
- Why It Matters: The current external-target evidence proves docs-only behavior on a non-platform repo, but it does not yet say how the bounded-code path behaves outside `agent-sdlc`.
- Current State: The second fixture family is now `target-code-small`, a tiny Node.js repo that reuses the same target-side CI and traceability kit while narrowing edits to a small code surface. The first two live bounded-code retries failed in useful ways on `src/task-summary.js` (`PR #2` / run `#57`, then `PR #4` / run `#58`), exposing how easily the provider can break behavior-sensitive exports. A third narrower retry then passed on `eval/target-code-small`: issue `#5` / comment `#162` -> task `trq-7d9a75db740f` -> session `ags-b02a30c22316` -> `PR #6` -> run `#59` (`success`), with bounded edits to `src/task-priority.js` and converged traceability.
- Evidence Class: `external target service evaluation`
- Next Action: Move out at the next maintenance pass unless an immediate follow-up is needed to turn the two failed retries into a narrower prompt or rubric improvement.
- Exit Path: Move out after the first bounded-code external-target run is captured and the canonical case note carries both the passed evidence and the earlier failed retries.
- Canonical Case: `docs/testing/items/TC-007-external-target-bounded-code-evaluation-baseline.md`
- Escalation Check: Update issue, roadmap, WBS, or ADR surfaces if the code-focused fixture reveals a new service-boundary or evaluation-model assumption beyond the existing docs-only baseline.
- Notes: This case should stay narrow on purpose; the goal is to compare service-evaluation behavior across fixture families without jumping to broader pilot claims. The first two failed retries are worth keeping because they show a real bounded-code quality failure mode even though the third retry passed.

## Change Log
- 2026-04-21: Initial version.
- 2026-04-21: Reopened `TC-003` after a fresh GUI run showed that the current default issue-comment path stops at `workspace-prepared` and still requires manual proposal continuation.
- 2026-04-21: Moved `TC-003` back out after issue `#11` and PR `#12` confirmed the GUI issue-comment path now auto-creates the proposal and root traceability file.
- 2026-04-21: Promoted the remaining host-side canonical traceability refresh gap into active item `TC-002`.
- 2026-04-21: Recorded the post-fix CLI half-live validation on PR `#18`, which removed the duplicate new-PR CI run while leaving the host-side canonical traceability refresh gap active.
- 2026-04-22: Marked `TC-002` passed after seeded local PR `#23` completed successful run `#41` and automatically converged the PR body plus both durable traceability copies.
- 2026-04-23: Added `TC-004` for the first config-selected agent execution adapter smoke path.
- 2026-04-23: Marked `TC-004` passed after provider-enabled DeepSeek execution created session `ags-cd9d3e289f02`, local proposal `PR #24`, passed provider-requested validation, and completed successful revalidation run `#45` with automatic host-side PR body sync for CI traceability.
- 2026-04-23: Expanded `TC-004` validation coverage to `documentation_update` through session `ags-0e18b7db5b88`, local proposal `PR #25`, and successful CI run `#46`.
- 2026-04-23: Expanded `TC-004` validation coverage to `review_follow_up` (`PR #26`, run `#47`) and `ci_failure_investigation` (`PR #27`, run `#48`) with investigation-path edit guardrails.
- 2026-04-23: Added `TC-005` and marked the first manual real-AI connectivity flow passed.
- 2026-04-23: Reopened `TC-004` and `TC-005` after correcting local CI evidence: runs `#46`-`#49` failed from stale forge-seeded proposal branches, and fresh post-fix revalidation is now required.
- 2026-04-23: Marked `TC-004` and `TC-005` passed again after fresh post-fix provider runs completed for all enabled tokens with successful local CI runs `#51`-`#54` and converged traceability.
- 2026-04-24: Added `TC-006` and marked the existing active cases as platform-regression evidence while the first external target-repo service-evaluation baseline is still being introduced.
- 2026-04-24: Moved `TC-006` to ready after adding the first `target-docs` fixture plus provisioning/reset commands.
- 2026-04-24: Marked `TC-006` passed after post-fix external-target run `#002` completed successfully on `eval/target-docs` with PR `#4` and CI run `#56`.
- 2026-04-24: Added `TC-007` to track the second external-target fixture family and the first bounded-code service-evaluation baseline.
- 2026-04-24: Marked `TC-007` passed after narrowed retry `external-target-code-20260424-003` completed successfully on `eval/target-code-small` with PR `#6` and CI run `#59`, while retaining the first two failed retries as useful evaluation evidence.
