# Test Dashboard

## Document Metadata
- Version: 0.1
- Status: Active
- Last Updated: 2026-04-30
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
- 2026-04-24: Added `TC-008` as the delivery-oriented manual acceptance flow for the current P1 slice, linked to the new `docs/phase1-deliverable.md` comparison and acceptance packaging.
- 2026-04-29: Marked `TC-008` passed after writing back the 2026-04-24 full manual walkthrough and refreshed `TC-006` / `TC-007` with new external-target rerun evidence.
- 2026-04-29: Added `TC-009` to keep the new issue-thread rejection feedback covered and to track the still-needed deterministic no-op repro.
- 2026-04-29: Reframed `TC-009` as deferred follow-up after applying the current Phase 1 close interpretation that deterministic no-op repro is a coverage gap rather than a baseline blocker.
- 2026-04-29: Added `TC-010` after a fresh docs-safe run on `README.md` exposed a large-file truncation regression caused by partial context plus full-file rewrite response requirements.
- 2026-04-30: Moved `TC-010` to ready after landing the fail-closed guardrail plus safe fragment-edit support and verifying both behaviors through deterministic local stubbed execution.
- 2026-04-30: Archived the passed or deferred Phase 1 close-window cases after live rerun evidence on `PR #44` / run `#71` cleared `TC-010`, leaving `TC-001` as the primary always-ready diagnostic case.
