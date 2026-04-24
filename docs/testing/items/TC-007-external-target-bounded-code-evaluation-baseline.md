# TC-007: External Target Bounded-Code Evaluation Baseline

## Metadata
- Test ID: TC-007
- Status: Ready
- Last Updated: 2026-04-24
- Owner: Project Maintainer
- Mode: External target evaluation
- Related Docs / WBS: `docs/policies/service-state-and-evaluation.md`; WBS `3.10`, `3.11`
- Source Dashboard: docs/testing/test-dashboard.md
- Source Template: docs/templates/test-case.template.md

## Objective
Establish the first repeatable bounded-code service-evaluation case on a non-platform target repo so the project can compare a small code-edit workflow against the existing docs-only external-target evidence.

## Scope
This case is intended to cover:
- provisioning or resetting the `target-code-small` fixture
- running one bounded `@agent run code` task on a non-platform repo
- verifying that the resulting edits stay inside the intended code boundary
- capturing PR, CI, and traceability evidence distinct from platform regression

## Current State
- fixture path: `fixtures/targets/target-code-small/`
- local provision command: `npm run eval:target-code-small:provision`
- local reset command: `npm run eval:target-code-small:reset`
- seeded local forge target: `gitea:localhost:43000/eval/target-code-small`
- baseline status: fixture and command surface validated, first bounded-code evaluation run still pending

## Preconditions
- local Gitea environment and runner are up
- the platform repo has already generated local bootstrap config and local agent-execution config when real provider execution is desired
- `npm run eval:target-code-small:provision` or `npm run eval:target-code-small:reset` has completed successfully
- the task-gateway and review-surface listeners are available

## Test Data
- Target repo name: `eval/target-code-small`
- Repository ref: `gitea:localhost:43000/eval/target-code-small`
- Provision command: `npm run eval:target-code-small:provision`
- Reset command: `npm run eval:target-code-small:reset`
- Fixture source: `fixtures/targets/target-code-small/`
- Task token: `@agent run code`
- Suggested first summary: `Add a short priority label to each task summary and keep edits inside src/** plus README.md if needed`
- Expected editable paths:
  - `src/**`
  - `README.md`
- Expected validation commands:
  - `npm run validate:platform`
  - `npm run typecheck`
- Initial rubric:
  - edits stay inside the bounded code surface
  - PR is created against `eval/target-code-small`
  - target-repo CI completes with visible verification metadata
  - host-side traceability converges without manual repair
  - resulting code change is understandable and reviewable without broad rewrite

## Steps
1. Provision or reset the external target repo.
2. Trigger one bounded `@agent run code` task against `eval/target-code-small`.
3. Observe task request, session, proposal PR, CI result, and traceability.
4. Compare the resulting edits against the intended code boundary and rubric.
5. Record whether the result is strong enough to count as internal-eval evidence for bounded-code service behavior.

## Expected Results
- a non-platform code-focused target repo produces a bounded PR and CI result
- the case gives service-evaluation evidence for `code`, not only for `docs`
- the project has a reusable second external-target fixture family for later comparison work

## Evidence To Capture
- provision/reset output
- task request and session IDs
- proposal PR and CI run references
- changed file list
- rubric outcome and any review-quality observations

## Cleanup
- reset `eval/target-code-small` before the next clean comparison run if needed
- close or keep the proposal PR according to the active review window

## Change Log
- 2026-04-24: Initial version.
- 2026-04-24: Updated after validating the `target-code-small` fixture scripts and provision command.
