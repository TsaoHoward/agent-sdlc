# Testing Workflow

## Document Metadata
- Version: 0.1
- Status: Active
- Last Updated: 2026-04-29
- Owner: Project Maintainer

## Purpose
This directory is the durable testing workflow surface for the repository.

Use it to:
- understand the current local validation strategy
- understand the current Phase 1 delivery-oriented manual acceptance path
- run repeatable CLI and GUI smoke procedures
- find stable local test data such as URLs, usernames, passwords, and repo names
- track active near-term testing work separately from long-lived test procedures
- move completed or no-longer-near-term test items out of the active dashboard without losing useful history
- distinguish platform self-test evidence from external target service-evaluation evidence

## Recommended Reading Order
1. `docs/testing/test-plan.md`
2. `docs/testing/test-framework.md`
3. `docs/phase1-deliverable.md`
4. `docs/user-guide.zh-TW.md`
5. `docs/testing/local-test-procedures.md`
6. `docs/testing/test-dashboard.md`
7. `docs/testing/items/*.md` referenced by active dashboard items
8. `docs/testing/test-archive.md`
9. `docs/policies/testing-management.md`

## Workflow Map
| Document | Use It For | When To Update |
|---|---|---|
| `docs/testing/test-plan.md` | stable scope, entry criteria, exit criteria, and default local data | when the durable test scope or local defaults change |
| `docs/testing/test-framework.md` | execution modes, evidence surfaces, and write-back rules | when the testing model or expected evidence changes |
| `docs/phase1-deliverable.md` | current P1 delivery scope, docs-vs-code interpretation, and manual acceptance order | when the current P1 delivery claim or acceptance sequence changes |
| `docs/testing/local-test-procedures.md` | operator-facing CLI and GUI walkthroughs | when commands, credentials, URLs, or observation steps change |
| `docs/testing/test-dashboard.md` | active near-term test work that still deserves attention | when current-cycle validation state changes |
| `docs/testing/items/` | canonical case definitions and exact procedures | when a test case needs stable, detailed steps |
| `docs/testing/test-archive.md` | lightweight history for items moved out of the active dashboard | when passed, deferred, or retired items leave the dashboard |

## Recommended Execution Order
For a fresh local validation pass:
1. bring up the local environment from `docs/testing/local-test-procedures.md`
2. run `TC-001` to confirm intake and session-start boundaries
3. run `TC-002` to confirm proposal, traceability, and review-sync surfaces
4. run `TC-004` when agent execution adapter behavior changes or provider-enabled validation is in scope
5. run `TC-005` when you need the operator-facing real AI connectivity checklist
6. run `TC-003` when you need the full operator-facing GUI path
7. treat those current runs as platform self-test / platform regression when they target `howard/agent-sdlc`
8. run `TC-006` when you need service-evaluation evidence beyond the platform repo, starting with `npm run eval:target-docs:provision` or `npm run eval:target-docs:reset`
9. run `TC-007` when you need the first bounded-code service-evaluation case beyond docs-only evidence, starting with `npm run eval:target-code-small:provision` or `npm run eval:target-code-small:reset`
10. run `TC-008` when you want one delivery-oriented manual acceptance pass that chains the current P1 procedures in their intended order
11. write any new gap back into `docs/testing/test-dashboard.md`, then update issue or decision docs if the result changes project-level understanding

The latest reproducible live issue-comment reference is now the 2026-04-24 manual-acceptance rerun on `howard/agent-sdlc#33`, which created task request `trq-08c59229d0a9`, session `ags-e52b3bc208c0`, proposal `PR #34`, and successful UI run `#56`. The latest replay/proposal refresh path in that same walkthrough also reconfirmed `trq-c9b2fa3064fb` -> `ags-796b088fafa1` with updated `PR #1` CI convergence after stale-seed preflight and reseed. Provider-enabled agent execution evidence remains available across all currently enabled issue-comment tokens, and the same walkthrough also refreshed external-target proofs on `eval/target-docs` (`trq-530938b564d7`, `PR #6`, UI run `#3`) and `eval/target-code-small` (`trq-7f9ab84dbce5`, `PR #8`, UI run `#4` after one fail-closed overlong-summary rejection).

Current correction status (2026-04-23): stale-seed CI failures in runs `#46`-`#49` are resolved by reseeding local forge `main` and enforcing proposal stale-seed preflight before branch push.

Current evidence classification (2026-04-24):
- the seeded local `howard/agent-sdlc` path remains the primary platform self-test / platform regression path
- broader service-quality claims now require external target-repo evaluation per ADR-0009 and `docs/policies/service-state-and-evaluation.md`
- the first valid external-target evidence set is now `eval/target-docs` issue `#3` / comment `#153` -> task `trq-f77d70ed7f92` -> session `ags-7f12724630cc` -> PR `#4` -> CI run `#56` (`success`)
- the first valid bounded-code external-target evidence set is now `eval/target-code-small` issue `#5` / comment `#162` -> task `trq-7d9a75db740f` -> session `ags-b02a30c22316` -> PR `#6` -> CI run `#59` (`success`)

## Stable Local Test Data
| Item | Value |
|---|---|
| Gitea UI | `http://localhost:43000/` |
| Login page | `http://localhost:43000/user/login` |
| Admin account | `agent-admin` / `agent-dev-password` |
| Operator account | `howard` / `agent-dev-password` |
| Default local repo | `howard/agent-sdlc` |
| Default branch | `main` |
| Issue-comment listener | `http://127.0.0.1:4010/hooks/gitea/issue-comment` |
| Review-follow-up listener | `http://127.0.0.1:4011/hooks/gitea/pull-request-review` |
| Runner container | `agent-sdlc-gitea-runner` |

The password values above are generated into ignored local Gitea bootstrap config by `npm run dev:gitea-bootstrap-config`; the tracked template keeps the config shape and env-var names without storing those actual local password values. Runner and worker-runtime defaults also come from that template/local bootstrap config.

## Write-In And Move-Out Rule
- write active or newly discovered testing work into `docs/testing/test-dashboard.md`
- keep durable procedures in `docs/testing/items/`
- move `Passed`, `Deferred`, or `Retired` items out of the active dashboard when they no longer need attention
- record the move-out in `docs/testing/test-archive.md` when lightweight historical context is still useful

See `docs/policies/testing-management.md` for the full governance rule set.

## Change Log
- 2026-04-21: Initial version.
- 2026-04-23: Added `TC-004` to the recommended execution order for the first agent execution adapter slice.
- 2026-04-23: Recorded provider-enabled `TC-004` validation through a session-backed local proposal.
- 2026-04-23: Recorded provider-enabled `TC-004` validation for `documentation_update` through session `ags-0e18b7db5b88`, PR `#25`, and run `#46`.
- 2026-04-23: Expanded provider-enabled `TC-004` validation to `review_follow_up` and `ci_failure_investigation`, and added `TC-005` as the manual real-AI connectivity runbook entrypoint.
- 2026-04-23: Corrected CI evidence for runs `#46`-`#49` after identifying stale forge seeding as the common failure root cause; reopened post-fix revalidation for multi-token provider paths.
- 2026-04-23: Recorded fresh post-fix provider revalidation across all enabled tokens with successful runs `#51`-`#54`, and kept stale-seed preflight as the prevention guardrail.
- 2026-04-24: Added the platform-regression versus external-target evidence distinction and the planned `TC-006` service-evaluation baseline.
- 2026-04-24: Recorded the first concrete `target-docs` external-target baseline plus its local provision/reset commands.
- 2026-04-24: Recorded the first valid external-target evidence set on `eval/target-docs` after fixing nested-fixture seeding.
- 2026-04-24: Added `TC-007` and the `target-code-small` fixture family as the next external-target bounded-code evaluation baseline.
- 2026-04-24: Recorded the first valid bounded-code external-target evidence set on `eval/target-code-small` after two earlier failed retries exposed behavior-sensitive bounded-code failure modes.
- 2026-04-24: Added `docs/phase1-deliverable.md` and `TC-008` as the delivery-oriented manual acceptance entrypoint for the current P1 slice.
- 2026-04-29: Added the concise Traditional Chinese guide to the recommended reading order and recorded the fresh 2026-04-24 manual-acceptance evidence set.
