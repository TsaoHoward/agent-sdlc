# TC-008: Phase 1 Manual Deliver Acceptance

## Metadata
- Test ID: TC-008
- Status: Passed
- Last Updated: 2026-04-29
- Owner: Project Maintainer
- Mode: Manual acceptance
- Related Docs / WBS: `docs/phase1-deliverable.md`; `docs/testing/local-test-procedures.md`; WBS `3.7`, `3.9`, `3.10`, `3.11`
- Source Dashboard: docs/testing/test-dashboard.md
- Source Template: docs/templates/test-case.template.md

## Objective
Provide one ordered manual acceptance flow for the current P1 slice so a maintainer can confirm platform regression, real-agent execution, and external-target evidence without reconstructing the intended sequence from multiple documents.

## Scope
This case is intended to cover:
- environment bring-up and local control-host health
- platform-regression validation of intake, session, proposal, CI, and review surfaces
- provider-backed execution confirmation for the current P1 real-agent slice
- external-target docs and bounded-code confirmation
- one explicit manual acceptance conclusion for the current P1 delivery state

## Preconditions
- local environment can be started from the repo-owned bootstrap commands
- the local Gitea runner is online when CI-linked validation is in scope
- if provider-backed validation is required, ignored local `config/agent-execution.yaml` exists with valid credentials
- `eval/target-docs` and `eval/target-code-small` can be provisioned or reset locally

## Test Data
- Delivery summary document: `docs/phase1-deliverable.md`
- Platform target repo: `howard/agent-sdlc`
- External target repos:
  - `eval/target-docs`
  - `eval/target-code-small`
- Canonical procedures reused by this case:
  - `TC-001`
  - `TC-002`
  - `TC-003`
  - `TC-004`
  - `TC-005`
  - `TC-006`
  - `TC-007`

## Steps
1. Read `docs/phase1-deliverable.md` and confirm the current service-state interpretation before running commands.
2. Bring up the local environment using the `Environment Bring-Up` section in `docs/testing/local-test-procedures.md`.
3. Run the platform-regression baseline in this order:
   - `TC-001`
   - `TC-002`
   - `TC-003`
4. Run the real-agent slice confirmation:
   - `TC-004` to confirm adapter/config posture
   - `TC-005` to confirm real provider connectivity
5. Run the external-target docs checkpoint:
   - `TC-006`
6. Run the external-target bounded-code checkpoint:
   - `TC-007`
7. Record one acceptance conclusion using these labels:
   - `accepted for current P1 manual confirmation`
   - `accepted for platform regression only`
   - `accepted for docs-oriented external eval only`
   - `not accepted`
8. Write any discrepancy back into `docs/testing/test-dashboard.md` and `docs/issues/issue-dashboard.md` before closing the validation window.

## Latest Known Result
- Walkthrough date: 2026-04-24
- Acceptance label: `accepted for current P1 manual confirmation`
- Environment notes:
  - local Gitea, task gateway listener, and review-surface listener were running
  - `npm run dev:gitea-runner -- ensure-runner` confirmed the runner was online
  - provider config resolved from ignored local config with `enabled: true`, backend `deepseek`, mode `remote`, and model `deepseek-chat`
  - `dev:env:status` still reported `ENV-004 CI Environment: not bootstrapped locally yet` even though the runner was online; treat this as an observability inconsistency, not as a blocker for the passed result
- Platform-regression evidence:
  - replay intake/session: `trq-c9b2fa3064fb` -> `ags-796b088fafa1`
  - proposal/traceability after reseed preflight: `PR #1` -> UI run `#55`
  - live GUI-equivalent issue-comment path: issue `#33` / comment `#166` -> `trq-08c59229d0a9` -> `ags-e52b3bc208c0` -> `PR #34` -> UI run `#56`
- Real-agent execution evidence:
  - adapter artifact confirmed provider metadata, token usage, changed files, and successful validation command for session `ags-e52b3bc208c0`
  - durable traceability still showed successful coverage for `code`, `docs`, `review`, and `ci`
- External-target evidence:
  - docs rerun: issue `#5` / comment `#169` -> `trq-530938b564d7` -> `ags-cf7e0c1b0033` -> `PR #6` -> UI run `#3`
  - bounded-code rerun: issue `#7` / comment `#172` fail-closed because `summary:` length was `284`; shortened retry on comment `#173` then produced `trq-7f9ab84dbce5` -> `ags-f90ba2a103be` -> `PR #8` -> UI run `#4`
- Interpretation:
  - platform regression path is stable
  - docs external target remains the steadier first acceptance checkpoint
  - bounded-code external target is usable, but prompt length and scope discipline are part of the current P1 operating boundary

## Expected Results
- the platform regression path is confirmed first, before spending effort on external-target interpretation
- provider-backed execution is checked explicitly instead of being inferred only from earlier stored evidence
- external docs and external bounded-code behavior are compared in order
- the operator leaves with one explicit P1 acceptance conclusion rather than only scattered case results

## Evidence To Capture
- environment status output
- the latest task, session, proposal, and CI references from each stage
- whether provider-backed execution was enabled for this pass
- the final acceptance label selected in Step 7
- any observed difference between the docs-oriented and bounded-code external-target outcomes

## Cleanup
- shut down the local environment if desired
- reset external targets before the next clean acceptance pass
- close or preserve created issues and PRs according to the current local review window

## Change Log
- 2026-04-24: Initial version.
- 2026-04-29: Marked passed after writing back the 2026-04-24 full manual walkthrough, including the explicit acceptance label and the fresh docs/code external-target reruns.
