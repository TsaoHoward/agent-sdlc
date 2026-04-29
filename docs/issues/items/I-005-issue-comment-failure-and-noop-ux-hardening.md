# I-005: Issue-Comment Failure And No-Op UX Hardening

## Metadata
- Issue ID: I-005
- Status: Deferred
- Last Updated: 2026-04-29
- Owner: Project Maintainer
- Related Phase / WBS: `docs/roadmap.md` Phase 1; WBS `3.1`, `3.8`, `3.9`
- Source Dashboard: `docs/issues/issue-dashboard.md`
- Source Template: `docs/templates/issue-note.template.md`

## Summary
The current live issue-comment path now has a minimal bounded feedback surface for fail-closed intake, stale-forge proposal stops, and completed zero-edit no-op results.

That closes the worst UX gap, but it is not yet the final user-facing design.

## Why This Exists
Without visible status write-back, operators can interpret normal bounded failures as:
- webhook failure
- runtime crash
- provider outage
- missing permissions

That confusion is especially costly in the current Phase 1 local seeded-repo workflow because stale-forge preflight is a valid safety stop, not a hidden infrastructure defect.

## Landed Minimal P1 Behavior
The bounded P1 fix now does three things:
- malformed or unsupported `@agent` issue-comment requests can receive a bounded `agent-admin` explanation comment
- failed live continuation states such as stale-forge proposal preflight can write a bounded issue-thread status comment instead of stopping silently
- a completed provider run with zero repo file edits now stops before PR creation as a visible no-op rather than creating a traceability-only PR

Reply scope rule in the landed fix:
- feedback should apply only to comments that actually use the `@agent` command surface
- normal human discussion comments should not receive automatic agent status replies

## Follow-Up Design Space
Possible follow-up improvements include:
- explicit feedback taxonomy for `rejected`, `blocked`, `failed`, `noop`, and `proposal-created`
- duplicate-comment suppression when equivalent status was already written recently
- richer stale-forge remediation text with direct references to `docs/policies/branch-and-local-forge-sync.md`
- richer no-op explanation that distinguishes "already satisfied", "insufficient context", and "provider chose not to edit"
- optional success acknowledgement without turning the issue thread into a chat transcript
- operator-facing correlation fields such as `task_request_id` plus a direct PR link when a proposal exists

## State Storage Evaluation
The current Phase 1 file-backed state under `.agent-sdlc/` is still acceptable as a bootstrap persistence surface because it is:
- easy to inspect during local development
- compatible with the current CLI replay flow
- already aligned with the documented Phase 1 persistence contract

But it now has visible drawbacks:
- it pollutes the working repo with operational state
- searching across runs is clumsy compared with queryable storage
- retention, cleanup, and operator browsing are still awkward
- mixing durable planning docs with operational run records can blur repository hygiene

The likely next-step direction is not "remove all files immediately", but:
1. keep repo-visible file artifacts only where reviewer-facing traceability still benefits from them
2. evaluate moving task/session/event operational records to a dedicated local service store
3. preserve export or snapshot paths so replay/debug workflows do not regress

Candidate follow-up storage shapes to compare:
- local SQLite for single-node/operator-friendly queryability
- PostgreSQL when the control-plane service boundary becomes more persistent and multi-process coordination matters
- hybrid model: DB for operational state, file or PR-attached artifacts for reviewer-facing evidence

This is not a P1-default implementation change yet. If selected, it should be promoted through the decision backlog and likely ADR review because it affects persistence ownership and source-of-truth boundaries.

## Unified UX Discovery Mechanism
This class of UX gaps should not depend on ad hoc human memory or chat-only observations.

Recommended follow-up mechanism:
- keep a dedicated issue/dashboard surface for user-visible workflow friction and misleading states
- add canonical E2E cases that explicitly assert user-visible outcomes, not only backend artifacts
- include "silence / confusing status / misleading no-op" checks in the manual acceptance pack
- add periodic horizon analysis of current operator pain points, not only pass/fail regression status
- connect discovered UX gaps back into issue, testing, and decision docs in the same write-back pass

Concrete follow-up slices worth considering:
1. E2E assertions for rejection feedback, stale-forge feedback, and no-op feedback
2. a recurring UX review rubric inside `TC-008` or its successor acceptance flow
3. an issue-management convention for classifying operator confusion separately from backend defects

## Boundaries
This follow-up should stay inside the current Phase 1 architecture boundaries:
- task gateway remains the intake authority
- agent control remains the session authority
- CI remains the independent verifier
- the issue thread is only a bounded user-facing status surface, not the durable orchestration database

Do not use this follow-up to smuggle in:
- a new conversational agent control plane
- prompt-only workflow memory
- PR or CI ownership changes

## Recommended Next Decision
After the current P1 packaging window, choose one narrow next slice:
1. status taxonomy plus duplicate suppression
2. richer stale-forge remediation
3. richer no-op explanation
4. storage evolution evaluation for operational state
5. unified UX discovery and acceptance coverage

## Change Log
- 2026-04-29: Initial version after landing the minimal bounded issue-thread feedback and no-op guardrail fix.
