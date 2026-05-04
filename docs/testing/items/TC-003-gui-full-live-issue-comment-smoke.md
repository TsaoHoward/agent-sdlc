# TC-003: GUI Full Live Issue-Comment Smoke

## Metadata
- Test ID: TC-003
- Status: Passed
- Last Updated: 2026-04-21
- Owner: Project Maintainer
- Mode: GUI live
- Related Docs / WBS: `docs/testing/local-test-procedures.md`; `docs/environment-bootstrap.md`; WBS `3.1`-`3.7`
- Source Dashboard: docs/testing/test-dashboard.md
- Source Template: docs/templates/test-case.template.md

## Objective
Verify the operator-facing local path from a live Gitea issue comment through task intake and session start, and confirm whether PR creation happens automatically or still requires a manual proposal step.

Latest known fresh result:
- Date: 2026-04-21
- Issue: `howard/agent-sdlc#11`
- Task request: `trq-bd85673302e7`
- Session: `ags-335855297620`
- Proposal PR: `#12`
- Result: after restarting the managed listeners with the strengthened automation path, the live issue comment created the task, auto-started the session, auto-created the proposal PR, and wrote a root traceability file without manual `proposal-surface` intervention

## Scope
This case covers:
- GUI issue creation and issue-comment command entry
- live issue-comment webhook intake
- auto-started session handoff
- whether real PR creation in local Gitea happens automatically from that path
- the transition into proposal, CI visibility, and live follow-up behavior through PR close and reopen

## Preconditions
- `powershell -ExecutionPolicy Bypass -File scripts/dev/manage-dev-environment.ps1 -Command up` has completed
- `npm run dev:gitea-runner -- ensure-runner` reports an online local runner
- the operator can log in to local Gitea as `howard`
- the default repo `howard/agent-sdlc` exists

## Test Data
- Gitea URL: `http://localhost:43000/`
- operator username: `howard`
- operator password: `agent-dev-password`
- repo: `howard/agent-sdlc`
- command text:

```text
@agent run code
summary: TC-003 full live issue-comment smoke
```

## Steps
1. Sign in to local Gitea as `howard`.
2. Open repo `howard/agent-sdlc`.
3. Create a fresh issue for the test run.
4. Add the command comment shown in the Test Data section.
5. Observe the newest task-request and session records under `.agent-sdlc/state/`.
6. Confirm that a new PR appears automatically in the repo UI.
7. Open the resulting PR and inspect the traceability block.
8. Observe the corresponding Actions run in local Gitea.
9. Close the PR, wait for the review-follow-up listener to process the event, then reopen the same PR.
10. Re-open the newest traceability file and confirm the PR body refreshed automatically.

## Expected Results
- the live issue comment creates a retained source event plus a new task request
- a session starts automatically for the accepted task
- a real PR appears automatically in local Gitea
- the root traceability file for that task exists without manual `proposal-surface` intervention
- CI run visibility and PR follow-up behavior still work from that auto-created proposal
- PR close and reopen events should reach the bootstrap-managed review listener and refresh durable traceability without manual replay after the PR exists

## Evidence To Capture
- issue URL and comment text
- newest task-request JSON
- newest session JSON
- whether a PR appeared automatically without manual continuation
- PR URL and PR body traceability block
- Actions run URL or run number
- newest traceability JSON after close or reopen
- optional `hook_task` proof when webhook delivery debugging is needed

## Cleanup
Close the issue or PR only if the current validation window no longer needs them as evidence. Otherwise leave them in place and note that they belong to `TC-003`.

## Change Log
- 2026-04-21: Initial version.
- 2026-04-21: Reopened the case as failed after a fresh GUI run on issue `#7` confirmed that the current default issue-comment path stopped at `workspace-prepared` and did not auto-create the PR.
- 2026-04-21: Marked the case passed after issue `#11` and PR `#12` confirmed that the strengthened listener path now auto-creates the proposal and root traceability file.
