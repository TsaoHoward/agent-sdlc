# TC-006: External Target Service-Evaluation Baseline

## Metadata
- Test ID: TC-006
- Status: Passed
- Last Updated: 2026-04-29
- Owner: Project Maintainer
- Mode: External target evaluation
- Related Docs / WBS: ADR-0009; `docs/policies/service-state-and-evaluation.md`; WBS `3.10`, `3.11`
- Source Dashboard: docs/testing/test-dashboard.md
- Source Template: docs/templates/test-case.template.md

## Objective
Run the first repeatable non-platform target-repo procedure so the project can collect service-evaluation evidence that is distinct from platform self-test.

## Scope
This case is intended to cover:
- provisioning or resetting a controlled external target repo
- running one bounded documentation workflow against that repo
- capturing PR, CI, and traceability evidence for a non-platform codebase
- scoring the result as service evaluation rather than only as platform regression

## Current State
This case now has a concrete baseline:
- fixture path: `fixtures/targets/target-docs/`
- local provision command: `npm run eval:target-docs:provision`
- local reset command: `npm run eval:target-docs:reset`
- seeded local forge target: `gitea:localhost:43000/eval/target-docs`

The first post-fix bounded docs run completed successfully, and a fresh 2026-04-24 manual rerun also completed successfully. The current local `howard/agent-sdlc` seeded repo still remains the main platform-regression baseline for platform self-test, while `eval/target-docs` now provides repeatable external-target service-evaluation evidence.

## Latest Known Result
- Date: 2026-04-24
- Fixture: `fixtures/targets/target-docs/`
- Local repo: `eval/target-docs`
- Trigger issue/comment: issue `#5`, comment `#169`
- Task/session: `trq-530938b564d7` -> `ags-cf7e0c1b0033`
- Proposal PR: `#6`
- CI run:
  - UI run number `#3` (`success`)
  - internal workflow run id `62`
- Changed files:
  - `README.md`
  - `docs/faq.md`
- Validation command outcome:
  - `npm run validate:platform` -> `passed`
- Final traceability summary:
  - `ci.ci_status=success`
  - `review.status=ready-for-human-review`
  - `review.proposal_body_sync_status=synced`

## Earlier Passed Result
- Date: 2026-04-24
- Trigger issue/comment: issue `#3`, comment `#153`
- Task/session: `trq-f77d70ed7f92` -> `ags-7f12724630cc`
- Proposal PR: `#4`
- CI run: UI run number `#56` (`success`)

## Known Correction
- The earlier trigger `external-target-eval-20260424-001` should not be treated as valid service-evaluation evidence for the target fixture.
- Root cause: `ensure-local-gitea-repo --seed-from <fixture-subdirectory>` originally pushed the parent platform repo `HEAD` when the seed path was a nested directory inside the main git worktree.
- Fix: the seeding helper now snapshots nested fixture directories into a temporary git repo and reports `seed_strategy: directory-snapshot` before pushing to local Gitea.
- Post-fix validation: `npm run eval:target-docs:reset` now reseeds `eval/target-docs` correctly, and the passed result above was collected after that fix.

## Preconditions
- local Gitea environment and runner are up
- if `npm run dev:env:status` reports `ENV-004 CI Environment: not bootstrapped locally yet`, bootstrap the runner before expecting target-repo CI evidence
- the platform repo has already generated local bootstrap config and, when real provider execution is desired, local `config/agent-execution.yaml`
- `npm run eval:target-docs:provision` or `npm run eval:target-docs:reset` has completed successfully
- the review-surface webhook listener is available so target-repo CI can post host traceability callbacks
- the selected task uses the `docs` token or equivalent `documentation_update` task class

## Test Data
- Target repo name: `eval/target-docs`
- Repository ref: `gitea:localhost:43000/eval/target-docs`
- Provision command: `npm run eval:target-docs:provision`
- Reset command: `npm run eval:target-docs:reset`
- Fixture source: `fixtures/targets/target-docs/`
- Task token: `@agent run docs`
- Suggested first summary: `Add a short onboarding note to README.md and one FAQ answer under docs/faq.md`
- Expected editable paths:
  - `README.md`
  - `docs/**`
- Expected validation commands:
  - `npm run validate:platform`
  - `npm run typecheck`
- Expected CI behavior:
  - target-repo workflow runs in `eval/target-docs`
  - local traceability artifact may end with `review.proposal_body_sync_status=deferred-to-host-sync`
  - host callback should still refresh canonical platform-side traceability and PR body state
- Initial rubric:
  - edits stay inside `README.md` and `docs/**`
  - PR is created against `eval/target-docs`
  - target-repo CI completes with a visible run and verification metadata artifact
  - host-side traceability sync accepts the target-repo CI payload
  - change quality is acceptable for human review without broad manual rewrite

## Steps
1. Provision or reset the external target repo.
   Use `npm run eval:target-docs:reset` unless this is the first local seed.
2. Trigger one bounded task against that repo.
   Recommended first slice: a docs-only issue comment on `eval/target-docs` using `@agent run docs`.
3. Observe task request, session, proposal PR, CI result, and traceability.
4. Compare the resulting edits against the case boundary and rubric.
5. Record whether the outcome is suitable as internal-eval evidence for that task class.

## Expected Results
- a non-platform target repo produces a bounded PR and CI result
- evidence clearly distinguishes this run from platform self-test
- the case provides reusable service-evaluation evidence for later promotion discussions

## Evidence To Capture
- target repo reset/provision evidence
- task request and session IDs
- proposal PR and CI run references
- changed file list from session evidence or PR diff
- rubric result or evaluator summary

## Cleanup
- reset `eval/target-docs` before the next run if a clean baseline is needed
- close or keep the evaluation PR according to the current review window
- if the fixture itself changes, reseed the repo before drawing comparisons across runs

## Change Log
- 2026-04-24: Initial draft.
- 2026-04-24: Moved to ready after adding the first `target-docs` fixture and local provision/reset command surface.
- 2026-04-24: Marked passed after post-fix run `external-target-eval-20260424-002` completed with task `trq-f77d70ed7f92`, session `ags-7f12724630cc`, PR `#4`, and successful CI run `#56`.
- 2026-04-29: Refreshed the latest-known result with the 2026-04-24 manual rerun on issue `#5` / comment `#169`, which completed as task `trq-530938b564d7`, session `ags-cf7e0c1b0033`, PR `#6`, and successful UI run `#3`.
