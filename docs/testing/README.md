# Testing Workflow

## Document Metadata
- Version: 0.1
- Status: Active
- Last Updated: 2026-04-24
- Owner: Project Maintainer

## Purpose
This directory is the durable testing workflow surface for the repository.

Use it to:
- understand the current local validation strategy
- run repeatable CLI and GUI smoke procedures
- find stable local test data such as URLs, usernames, passwords, and repo names
- track active near-term testing work separately from long-lived test procedures
- move completed or no-longer-near-term test items out of the active dashboard without losing useful history
- distinguish platform self-test evidence from external target service-evaluation evidence

## Recommended Reading Order
1. `docs/testing/test-plan.md`
2. `docs/testing/test-framework.md`
3. `docs/testing/local-test-procedures.md`
4. `docs/testing/test-dashboard.md`
5. `docs/testing/items/*.md` referenced by active dashboard items
6. `docs/testing/test-archive.md`
7. `docs/policies/testing-management.md`

## Workflow Map
| Document | Use It For | When To Update |
|---|---|---|
| `docs/testing/test-plan.md` | stable scope, entry criteria, exit criteria, and default local data | when the durable test scope or local defaults change |
| `docs/testing/test-framework.md` | execution modes, evidence surfaces, and write-back rules | when the testing model or expected evidence changes |
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
10. write any new gap back into `docs/testing/test-dashboard.md`, then update issue or decision docs if the result changes project-level understanding

The latest reproducible live issue-comment reference is the 2026-04-21 run on `howard/agent-sdlc#11`, which created task request `trq-bd85673302e7`, session `ags-335855297620`, root traceability `.agent-sdlc/traceability/trq-bd85673302e7.json`, and proposal `PR #12` automatically after the strengthened listener path was deployed. The latest CLI half-live verification after commit `292f535` then created synthetic task request `trq-route1-hostsync-final-20260421225724`, session `ags-9c860e1f0026`, and proposal `PR #23`, which produced one successful `pull_request` run (`#41`) and automatically converged the PR body, host root traceability file, and session-local workspace copy. Provider-enabled agent execution validation has now been revalidated across all currently enabled issue-comment tokens with fresh post-fix evidence: `code` (`trq-c9b2fa3064fb`, `PR #1`, run `#51`), `docs` (`trq-8dc2bbe48812`, `PR #30`, run `#52`), `review` (`trq-fd8ca8f8d18f`, `PR #31`, run `#53`), and `ci` (`trq-7765e00f85d4`, `PR #32`, run `#54`).

Current correction status (2026-04-23): stale-seed CI failures in runs `#46`-`#49` are resolved by reseeding local forge `main` and enforcing proposal stale-seed preflight before branch push.

Current evidence classification (2026-04-24):
- the seeded local `howard/agent-sdlc` path remains the primary platform self-test / platform regression path
- broader service-quality claims now require external target-repo evaluation per ADR-0009 and `docs/policies/service-state-and-evaluation.md`
- the first valid external-target evidence set is now `eval/target-docs` issue `#3` / comment `#153` -> task `trq-f77d70ed7f92` -> session `ags-7f12724630cc` -> PR `#4` -> CI run `#56` (`success`)
- the second fixture family `eval/target-code-small` is now the next bounded-code service-evaluation baseline, but it does not count as evidence until `TC-007` captures a real run

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
