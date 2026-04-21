# TC-002: CLI Proposal And Traceability Smoke

## Metadata
- Test ID: TC-002
- Status: In Progress
- Last Updated: 2026-04-21
- Owner: Project Maintainer
- Mode: CLI half-live
- Related Docs / WBS: `docs/testing/local-test-procedures.md`; `docs/architecture/pr-and-ci-path-definition.md`; `docs/architecture/lifecycle-traceability-contract.md`; WBS `3.4`, `3.5`, `3.6`
- Source Dashboard: docs/testing/test-dashboard.md
- Source Template: docs/templates/test-case.template.md

## Objective
Verify that the local forge can receive a proposal from the CLI path, produce traceability metadata, and accept direct review-sync refreshes without requiring a live issue-comment trigger.

Latest known result:
- Date: 2026-04-21
- Task request: `trq-route1-postfix-20260421111452`
- Proposal PR: `#18`
- Result: the post-fix proposal path created one successful `pull_request` CI run (`#37`) without the earlier duplicate sync-triggered second run, and the PR body converged automatically to `CI: success` / `ready for human review`, but the host root traceability file and session-local workspace copy still stayed at pre-CI state until a later host-side sync event refreshed them

## Scope
This case covers:
- proposal creation from a session record
- traceability write-back
- PR-body refresh
- direct review-sync command paths

## Preconditions
- local Gitea is running
- the default local repo `howard/agent-sdlc` exists
- the local runner is online when CI-linked observation is in scope
- a fresh or existing session record is available under `.agent-sdlc/state/agent-sessions/`

## Test Data
- default repo: `howard/agent-sdlc`
- forge base URL: `http://localhost:43000/`
- proposal traceability path: `.agent-sdlc/traceability/<task_request_id>.json`

## Steps
1. Ensure the local repo exists and is seeded from the current workspace:

```powershell
npm run dev:gitea-repo -- ensure-local-repo --owner howard --repo agent-sdlc --seed-from .
```

2. Select the newest session and create a PR:

```powershell
$latestSession = Get-ChildItem .agent-sdlc/state/agent-sessions/*.json | Sort-Object LastWriteTime -Descending | Select-Object -First 1
node scripts/proposal-surface.js create-gitea-pr --session $latestSession.FullName
```

3. Open the newest traceability JSON under `.agent-sdlc/traceability/`.
4. Open the PR URL from that traceability file in local Gitea and inspect the `## Agent Traceability` block.
5. Refresh review state directly from the proposal:

```powershell
node scripts/review-surface.js sync-gitea-pr-review-outcome --proposal gitea:localhost:43000/howard/agent-sdlc#pull/<index>
```

## Expected Results
- a real PR exists in local Gitea
- the traceability file includes `proposal_ref`, `proposal_url`, and proposal state fields
- the PR body shows the traceability block
- when CI completes, the durable host-side traceability view should converge with the reviewer-facing PR body without requiring an unrelated later event
- direct proposal-based review sync completes without degrading existing lifecycle data

## Evidence To Capture
- proposal-surface command output
- newest traceability JSON
- PR body traceability block
- optional CI run reference when available

## Cleanup
Close or keep the test PR according to the current validation window. If it remains open, note its purpose in the PR title or related test notes.

## Change Log
- 2026-04-21: Initial version.
- 2026-04-21: Recorded the remaining host-side traceability-refresh gap after proposal PR `#12` showed CI success in the PR body before the root traceability file converged.
- 2026-04-21: Updated the latest known result after post-fix proposal PR `#18` confirmed that duplicate new-PR CI runs were removed while the host-side traceability-refresh gap remained.
