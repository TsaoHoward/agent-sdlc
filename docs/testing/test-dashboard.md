# Test Dashboard

## Document Metadata
- Version: 0.1
- Status: Active
- Last Updated: 2026-04-22
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
| TC-004 | Agent Execution Adapter Smoke | Ready | CLI replay | `docs/roadmap.md` Phase 1; WBS `3.9` | Validate the disabled-by-default evidence path now, then re-run with `DEEPSEEK_API_KEY` and `AGENT_SDLC_AGENT_EXECUTION_ENABLED=true` when provider-enabled validation is in scope | Move out after provider-enabled validation is either passed or split into a narrower active item |

## Test Items

### TC-001 - CLI Replay Intake And Session Smoke
- Status: `Ready`
- Mode: `CLI replay`
- Related Docs / WBS: `docs/testing/items/TC-001-cli-replay-intake-and-session-smoke.md`; WBS `3.1`, `3.2`, `3.3`
- Why It Matters: This is the fastest deterministic way to inspect task normalization and session-start boundaries without waiting on the live forge path.
- Current State: The current CLI replay path exists and is used as the first troubleshooting layer when live webhook validation is not necessary.
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
- Next Action: Re-run against future proposal-path changes so duplicate-CI and host-traceability regressions are caught early.
- Exit Path: Move out at the next maintenance pass if no new proposal, CI, or traceability regression reopens this path.
- Canonical Case: `docs/testing/items/TC-002-cli-proposal-and-traceability-smoke.md`
- Escalation Check: Open or update an issue when proposal, CI, or traceability linkage breaks in a way that blocks the Phase 1 closed loop.
- Notes: This case keeps the forge real while still letting the operator advance the lifecycle one command at a time, and it now carries the active host-traceability sync gap.

### TC-004 - Agent Execution Adapter Smoke
- Status: `Ready`
- Mode: `CLI replay`
- Related Docs / WBS: `docs/testing/items/TC-004-agent-execution-adapter-smoke.md`; WBS `3.9`
- Why It Matters: This is the first validation surface for the new config-selected agent execution adapter before it is trusted as part of the live issue-to-PR path.
- Current State: The disabled-by-default adapter path has been smoke-tested without API credentials and writes `agent-execution.json` evidence with provider/config metadata. Provider-enabled DeepSeek validation still needs real credentials.
- Next Action: Run the canonical case first in disabled mode, then repeat with `DEEPSEEK_API_KEY` and explicit enablement when the operator wants to validate real provider-backed edits.
- Exit Path: Move out after provider-enabled validation is either passed or split into a narrower active item.
- Canonical Case: `docs/testing/items/TC-004-agent-execution-adapter-smoke.md`
- Escalation Check: Update the decision backlog or ADRs only if provider validation shows the adapter must move orchestration, runtime, traceability, or policy ownership out of the current repo-owned boundaries.
- Notes: This case intentionally separates config/evidence validation from full live GUI validation so WBS `3.9` can harden without destabilizing the already-working closed loop.

## Change Log
- 2026-04-21: Initial version.
- 2026-04-21: Reopened `TC-003` after a fresh GUI run showed that the current default issue-comment path stops at `workspace-prepared` and still requires manual proposal continuation.
- 2026-04-21: Moved `TC-003` back out after issue `#11` and PR `#12` confirmed the GUI issue-comment path now auto-creates the proposal and root traceability file.
- 2026-04-21: Promoted the remaining host-side canonical traceability refresh gap into active item `TC-002`.
- 2026-04-21: Recorded the post-fix CLI half-live validation on PR `#18`, which removed the duplicate new-PR CI run while leaving the host-side canonical traceability refresh gap active.
- 2026-04-22: Marked `TC-002` passed after seeded local PR `#23` completed successful run `#41` and automatically converged the PR body plus both durable traceability copies.
- 2026-04-23: Added `TC-004` for the first config-selected agent execution adapter smoke path.
