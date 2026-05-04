# TC-001: CLI Replay Intake And Session Smoke

## Metadata
- Test ID: TC-001
- Status: Ready
- Last Updated: 2026-04-21
- Owner: Project Maintainer
- Mode: CLI replay
- Related Docs / WBS: `docs/testing/local-test-procedures.md`; `docs/architecture/task-intake-contract.md`; `docs/architecture/agent-control-integration-plan.md`; WBS `3.1`, `3.2`, `3.3`
- Source Dashboard: docs/testing/test-dashboard.md
- Source Template: docs/templates/test-case.template.md

## Objective
Verify that a bounded issue-comment event can be replayed into a normalized task request and then into a session record plus runtime artifacts without depending on live forge delivery.

## Scope
This case covers:
- issue-comment replay
- task-request persistence
- direct session start
- runtime artifact and workspace preparation

It does not require a live PR or live review action.

## Preconditions
- the workspace has `npm install` completed
- the repo root is the active working directory
- `powershell -ExecutionPolicy Bypass -File scripts/dev/manage-dev-environment.ps1 -Command up -SkipGitea` has completed, or the relevant state directories already exist

## Test Data
- example event file: `docs/examples/gitea-issue-comment-event.example.json`
- task-request output path: `.agent-sdlc/state/task-requests/`
- session output path: `.agent-sdlc/state/agent-sessions/`

## Steps
1. Run:

```powershell
node scripts/task-gateway.js normalize-gitea-issue-comment --event docs/examples/gitea-issue-comment-event.example.json
```

2. Open the newest task-request JSON under `.agent-sdlc/state/task-requests/`.
3. Run:

```powershell
$latestTask = Get-ChildItem .agent-sdlc/state/task-requests/*.json | Sort-Object LastWriteTime -Descending | Select-Object -First 1
node scripts/agent-control.js start-session --task-request $latestTask.FullName
```

4. Open the newest session JSON under `.agent-sdlc/state/agent-sessions/`.
5. Inspect `.agent-sdlc/runtime/` for the corresponding workspace and runtime artifacts.

## Expected Results
- a new task request exists and contains stable lifecycle fields such as `task_request_id`, `task_class`, `execution_profile_id`, and `approval_state`
- a new session record exists and contains `agent_session_id`, runtime capability information, and workspace/artifact references
- runtime preparation leaves observable artifacts under `.agent-sdlc/runtime/`

## Evidence To Capture
- latest task-request JSON
- latest session JSON
- runtime artifact or workspace listing

## Cleanup
No cleanup is required beyond optional review of the newest generated state files.

## Change Log
- 2026-04-21: Initial version.
