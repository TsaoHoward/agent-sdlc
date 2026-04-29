# TC-009: Issue-Comment Feedback Coverage

## Metadata
- Test ID: TC-009
- Status: In Progress
- Last Updated: 2026-04-29
- Owner: Project Maintainer
- Mode: GUI live / webhook replay
- Related Docs / WBS: `docs/testing/local-test-procedures.md`; `docs/user-guide.zh-TW.md`; WBS `3.1`, `3.8`, `3.9`
- Source Dashboard: `docs/testing/test-dashboard.md`
- Source Template: `docs/templates/test-case.template.md`

## Objective
Verify that the live issue-comment path no longer appears silent when:
- task intake rejects a malformed bounded command
- the live continuation path stops before PR creation because the agent produced zero repo file edits

## Scope
This case covers:
- issue-thread feedback for fail-closed intake rejection
- issue-thread feedback for zero-edit no-op stopping before PR creation
- operator-visible status wording in the issue thread

It does not replace:
- proposal/CI correctness coverage in `TC-002`, `TC-003`, or `TC-008`

## Preconditions
- the task-gateway webhook listener is running with the current workspace code
- local Gitea is reachable
- repo `howard/agent-sdlc` exists

## Case A - Rejection Feedback
### Test Data
Use an issue-comment payload that starts with `@agent` but violates the Phase 1 command contract, for example:

```text
@agent run docs
notes: should reject
```

### Procedure
1. Send the malformed issue-comment event through a live listener or a temporary listener that is running the current workspace code.
2. Confirm the webhook response is `status: rejected`.
3. Open the issue thread in Gitea.
4. Confirm a bounded `agent-admin` comment appears with the rejection reason.

### Latest Known Result
- Date: 2026-04-29
- Issue: `howard/agent-sdlc#35`
- Replay mode: temporary listener on port `4015`
- Visible feedback comment: `#188`
- Result: passed for rejection coverage

## Case B - No-Op Feedback
### Current Gap
The no-op stop is now implemented in `agent-control`, but provider behavior on repeated prompts is not deterministic enough to treat one historical task as a stable canonical repro.

### Required Future Proof
Capture one repeatable run where:
- agent execution completes with zero repo file edits
- no proposal PR is created
- the issue thread receives the bounded no-op explanation comment

## Evidence To Capture
- webhook response JSON
- issue URL
- visible `agent-admin` feedback comment ID and text
- session record when no-op coverage is exercised

## Exit Rule
This case can move to `Passed` once both rejection feedback and no-op feedback have stable repeatable evidence.

## Change Log
- 2026-04-29: Initial version after validating the rejection-feedback replay path and recording the remaining deterministic no-op repro gap.
