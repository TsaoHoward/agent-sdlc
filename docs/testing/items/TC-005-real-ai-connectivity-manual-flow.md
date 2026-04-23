# TC-005: Real AI Connectivity Manual Flow

## Metadata
- Test ID: TC-005
- Status: In Progress
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
- `@agent run code`: `trq-4faac7e2a74b` -> `ags-cd9d3e289f02` -> `PR #24` -> run `#45`
- `@agent run docs`: `trq-2de69af748b1` -> `ags-0e18b7db5b88` -> `PR #25` -> latest local run failed in `#46` after stale-branch finalize 401
- `@agent run review`: `trq-2644a836e239` -> `ags-94e3f03d2f6b` -> `PR #26` -> latest local run failed in `#47` after stale-branch finalize 401
- `@agent run ci`: `trq-859264e0df7f` -> `ags-c742088383aa` -> `PR #27` -> latest local run failed in `#48` after stale-branch finalize 401
- Correction summary: local runs `#46`-`#49` showed the same stale-seeded-branch `Finalize CI Traceability` failure mode; forge `main` reseed plus proposal preflight has landed and multi-token manual-flow convergence is pending revalidation

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
