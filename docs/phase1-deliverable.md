# Phase 1 Deliverable

## Document Metadata
- Version: 0.1
- Status: Active
- Last Updated: 2026-04-29
- Owner: Project Maintainer

## Purpose
This document is the current delivery-oriented summary for Phase 1.

Use it when you need one durable place to answer:
- what Phase 1 currently delivers
- what is still explicitly out of scope
- how to manually confirm the delivered behavior step by step
- how the current docs-oriented and bounded-code evidence should be interpreted
- how close-out should be judged without relying on chat-only memory

## Current Delivery Position
- Related roadmap phase: `docs/roadmap.md` Phase 1
- Primary WBS: `docs/wbs.md` WBS `3.1` through `3.11`
- Current service state: `Workbench` with fresh `Internal Eval` rerun evidence
- Not yet in scope: Phase 2 rollout, pilot promotion gates, production posture
- Current close-out note: the 2026-04-24 manual acceptance remains valid historical evidence. The 2026-04-29 large-file `documentation_update` truncation regression is now mitigated by a fail-closed guardrail plus safe fragment-edit support, but final WBS `3.9` close-out still awaits one live workflow rerun tracked under `I-006` / `TC-010`

## What Phase 1 Currently Delivers
- one live trigger surface: `Gitea issue comment -> @agent run <token>`
- normalized task intake with durable task-request records
- automatic session start for auto-approved task classes
- per-session runtime workspace preparation
- proposal surfacing as branch plus PR
- independent PR-linked CI verification
- durable traceability across task, session, proposal, CI, and review surfaces
- review-follow-up synchronization for review, close, and reopen events
- opt-in provider-backed execution for `docs`, `code`, `review`, and `ci`
- two external-target internal-eval baselines:
  - `eval/target-docs`
  - `eval/target-code-small`

## What Phase 1 Does Not Yet Claim
- additional intake paths such as labels, PR comments, or PR review comments
- pilot-readiness gates
- broader user rollout
- production operating commitments
- broad code-task reliability outside the current bounded summaries and fixtures

## Evidence Snapshot
### Platform Regression
- fresh manual acceptance replay on 2026-04-24:
  - CLI replay: `trq-c9b2fa3064fb` -> `ags-796b088fafa1`
  - proposal refresh after reseed preflight: `PR #1` -> UI run `#55`
  - live GUI-equivalent issue comment: issue `#33` / comment `#166` -> task `trq-08c59229d0a9` -> session `ags-e52b3bc208c0` -> `PR #34` -> UI run `#56`
- provider-backed token evidence remains available for all four tokens:
  - `code`: `PR #1`
  - `docs`: `PR #30`
  - `review`: `PR #31`
  - `ci`: `PR #32`

### External Target Service Evaluation
- docs-oriented fresh rerun: `eval/target-docs` issue `#5` / comment `#169` -> task `trq-530938b564d7` -> session `ags-cf7e0c1b0033` -> `PR #6` -> UI run `#3` (`success`)
- bounded-code fresh rerun: first attempt fail-closed because the `summary:` payload was `284` characters and exceeded the contract limit; retry on issue `#7` / comment `#173` then produced task `trq-7f9ab84dbce5` -> session `ags-f90ba2a103be` -> `PR #8` -> UI run `#4` (`success`)
- bounded-code comparison history still also includes two earlier model-quality failures on UI runs `#57` and `#58`

## Docs Vs Code Comparison
| Dimension | Docs External Target | Bounded-Code External Target |
|---|---|---|
| Repo | `eval/target-docs` | `eval/target-code-small` |
| Primary task form | `@agent run docs` | `@agent run code` |
| Passing edit scope | `README.md`, `docs/faq.md` | `src/task-priority.js` |
| Current outcome pattern | passed cleanly on the fresh rerun once the target repo was reset | first failed closed at intake on an overlong `summary:`, then passed after narrowing the request |
| Main failure signal | earlier fixture-seeding bug, not current task-quality regression | both command-contract sensitivity and behavior-sensitive code regressions |
| Manual acceptance use | first internal-eval baseline to confirm the service can operate outside the platform repo | second internal-eval baseline to confirm bounded code can work, but only under tighter human review |

### Current Interpretation
- `docs` is the more stable Phase 1 external-target capability and should be treated as the first manual acceptance checkpoint after platform regression is healthy.
- `code` is a valid Phase 1 capability, but the fresh rerun still showed that small bounded-code tasks depend on both intake-discipline and behavior-sensitive edit quality.
- The fresh fail-closed rejection on a `284`-character `summary:` is a useful P1 boundary signal, not merely operator error; command-contract compliance is part of the current service behavior.
- For manual acceptance, `docs` should be used to prove external-target continuity first, then `code` should be run as the stricter gate that checks edit quality rather than only lifecycle continuity.
- A fresh 2026-04-29 repo-local docs-safe run also revealed a separate contract-level risk: when a target markdown file exceeds the current `maxFileBytes` cap, the provider can receive only a partial file while still being asked to return complete content. That regression affects close-out judgment for WBS `3.9` even though the earlier 2026-04-24 acceptance evidence remains useful historical proof.

## Latest Manual Acceptance Outcome
- Run date: 2026-04-24
- Case: `TC-008`
- Acceptance label: `accepted for current P1 manual confirmation`
- Summary:
  - platform regression path passed
  - real-agent execution path passed
  - external docs target passed cleanly
  - external bounded-code target passed after one fail-closed retry on intake length

## Post-Acceptance Follow-Up
- On 2026-04-29, issue `#41` / comment `#193` -> task `trq-097cad6b8f77` -> session `ags-2736c300be71` -> PR `#42` showed that a small `documentation_update` against `README.md` could delete the unseen tail of a large file.
- The likely root cause is the current execution contract in `scripts/lib/agent-execution.js`: context files are truncated at `maxFileBytes: 8000`, but the provider response schema still requires complete file content.
- A narrow fail-closed guardrail now blocks provider rewrite of any file whose supplied context was truncated, and safe fragment-edit modes now allow bounded updates such as `insert_after` without regenerating the whole file.
- Deterministic local stubbed verification has already confirmed both that destructive replace is blocked and that a large truncated file can still be updated safely without losing its tail.
- This follow-up remains tracked under `I-006` and `TC-010`, and WBS `3.9` still waits for one live rerun before it can be treated as fully closed.

## Manual Acceptance Package
Use the following sequence when you want a step-by-step Phase 1 manual confirmation pass.

1. Read this document, then `docs/testing/README.md`.
2. Run `docs/testing/items/TC-008-phase1-manual-deliver-acceptance.md` as the master checklist.
3. Use the linked canonical cases from `TC-008` in this order:
   - `TC-001`
   - `TC-002`
   - `TC-003`
   - `TC-004`
   - `TC-005`
   - `TC-006`
   - `TC-007`
4. Write any failure back into `docs/testing/test-dashboard.md` and `docs/issues/issue-dashboard.md` before drawing a new Phase 1 readiness conclusion.

## Acceptance Interpretation
- If `TC-001` through `TC-003` fail, the Phase 1 closed loop is not currently healthy.
- If `TC-004` or `TC-005` fail while the earlier cases pass, the platform loop is still present but the Phase 1 real-agent execution slice is not currently revalidated.
- If `TC-006` fails while platform regression passes, the service-evaluation path is not currently revalidated beyond the platform repo.
- If `TC-007` fails while `TC-006` passes, the docs-oriented external-target path is still healthier than the bounded-code path, and Phase 1 should continue to describe code-task behavior as tighter and more review-sensitive than docs behavior.

## Related Documents
- `README.md`
- `docs/phase1-close-checklist.md`
- `docs/user-capability-matrix.md`
- `docs/testing/README.md`
- `docs/testing/local-test-procedures.md`
- `docs/testing/items/TC-006-external-target-service-evaluation-baseline.md`
- `docs/testing/items/TC-007-external-target-bounded-code-evaluation-baseline.md`
- `docs/testing/items/TC-008-phase1-manual-deliver-acceptance.md`

## Change Log
- 2026-04-24: Initial version.
- 2026-04-29: Recorded the fresh `TC-008` manual walkthrough results, including the updated docs-versus-code comparison and acceptance conclusion from the 2026-04-24 rerun.
- 2026-04-29: Linked the new Phase 1 close checklist as the durable close-out decision surface.
- 2026-04-29: Added the post-acceptance note that the large-file docs-update truncation regression now blocks final WBS `3.9` close-out despite the earlier accepted manual evidence.
- 2026-04-30: Updated the post-acceptance note after landing the fail-closed large-file guardrail and shifting the remaining close-out step to one live rerun.
- 2026-04-30: Expanded the post-acceptance note after adding safe fragment-edit support so large-file docs updates are no longer limited to fail-closed behavior only.
