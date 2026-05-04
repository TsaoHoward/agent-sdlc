# TC-005: Real AI Connectivity Manual Flow

## Metadata
- Test ID: TC-005
- Status: Passed
- Last Updated: 2026-04-23
- Owner: Project Maintainer
- Mode: CLI half-live
- Related Docs / WBS: `docs/testing/local-test-procedures.md`; WBS `3.7`, `3.9`
- Source Dashboard: docs/testing/test-dashboard.md
- Source Template: docs/templates/test-case.template.md

## Objective
Provide one operator-facing manual runbook that validates real provider connectivity from issue-command intent to session evidence, proposal PR, CI completion, and reviewer-facing traceability convergence.

## Scope
This case covers:
- local project-config resolution for real provider mode
- real API-backed execution across currently enabled issue-comment task tokens
- proposal and CI evidence for each run
- host-side proposal traceability convergence after CI

It does not replace long-term automation.

## Latest Known Result
- Date: 2026-04-23
- Config source: ignored `config/agent-execution.yaml`
- Provider: `deepseek` / `remote` / `deepseek-chat`
- `@agent run code`: `trq-c9b2fa3064fb` -> `ags-33be3cb8741c` -> `PR #1` -> run `#51` (success)
- `@agent run docs`: `trq-8dc2bbe48812` -> `ags-b8311df3ef0c` -> `PR #30` -> run `#52` (success)
- `@agent run review`: `trq-fd8ca8f8d18f` -> `ags-9f4217fcbdc7` -> `PR #31` -> run `#53` (success)
- `@agent run ci`: `trq-7765e00f85d4` -> `ags-327998def612` -> `PR #32` -> run `#54` (success)
- Convergence summary: all four traceability files now show `ci.ci_status=success`, `review.status=ready-for-human-review`, and `review.proposal_body_sync_status=synced`

## Preconditions
- local environment and runner are up
- ignored local `config/agent-execution.yaml` has:
  - `agentExecution.enabled: true`
  - `agentExecution.apiKey` set
  - all required `allowedTaskClasses` entries

## Steps
1. Verify real provider config is active:

```powershell
node -e "const {resolveAgentExecutionConfig}=require('./scripts/lib/agent-execution'); const r=resolveAgentExecutionConfig(process.cwd()); console.log(JSON.stringify({source:r.configSource, enabled:r.config.enabled, backend:r.config.backend, mode:r.config.mode, model:r.config.model, allowedTaskClasses:r.config.allowedTaskClasses, hasApiKey:Boolean(r.config.apiKey)}, null, 2));"
```

2. Validate local scripts before spending API calls:

```powershell
npm run validate:platform
npm run typecheck
```

3. For each token (`code`, `docs`, `review`, `ci`), trigger one bounded run through issue-comment replay or live issue comment, then start a session with auto proposal:
- `@agent run code`
- `@agent run docs`
- `@agent run review`
- `@agent run ci`

4. For each resulting task, verify:
- session record has `agent_execution.status=completed`
- `agent_execution.changed_files` is non-empty
- proposal PR exists and links back to traceability metadata

5. Wait for CI runs to finish and then sync proposal traceability when needed:

```powershell
node scripts/review-surface.js sync-gitea-proposal-traceability --proposal gitea:localhost:43000/howard/agent-sdlc#pull/<index>
```

6. Confirm each traceability file shows:
- `ci.ci_status=success`
- `review.status=ready-for-human-review`
- `review.proposal_body_sync_status=synced`

## Expected Results
- real provider calls succeed with project config as source of truth
- each supported token produces a bounded session outcome with durable evidence
- PR and CI linkage stays intact
- reviewer-facing traceability converges without requiring CI-local ignored credentials

## Evidence To Capture
- config resolution output with `hasApiKey=true`
- session IDs and proposal refs for all token runs
- CI run refs
- final traceability state for each task request

## Cleanup
Close or keep smoke-test PRs based on the current validation window and issue-dashboard guidance.

## Change Log
- 2026-04-23: Initial version.
- 2026-04-23: Reopened after correcting local CI evidence for PRs `#25`-`#29`; stale forge-seeded proposal branches caused `Finalize CI Traceability` 401 failures in runs `#46`-`#49`, so post-fix multi-token manual-flow revalidation is required.
- 2026-04-23: Marked passed after fresh post-fix multi-token revalidation succeeded for `code/docs/review/ci` with CI runs `#51`-`#54`.
