# Testing Workflow

## Document Metadata
- Version: 0.1
- Status: Active
- Last Updated: 2026-04-23
- Owner: Project Maintainer

## Purpose
This directory is the durable testing workflow surface for the repository.

Use it to:
- understand the current local validation strategy
- run repeatable CLI and GUI smoke procedures
- find stable local test data such as URLs, usernames, passwords, and repo names
- track active near-term testing work separately from long-lived test procedures
- move completed or no-longer-near-term test items out of the active dashboard without losing useful history

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
7. write any new gap back into `docs/testing/test-dashboard.md`, then update issue or decision docs if the result changes project-level understanding

The latest reproducible live issue-comment reference is the 2026-04-21 run on `howard/agent-sdlc#11`, which created task request `trq-bd85673302e7`, session `ags-335855297620`, root traceability `.agent-sdlc/traceability/trq-bd85673302e7.json`, and proposal `PR #12` automatically after the strengthened listener path was deployed. The latest CLI half-live verification after commit `292f535` then created synthetic task request `trq-route1-hostsync-final-20260421225724`, session `ags-9c860e1f0026`, and proposal `PR #23`, which produced one successful `pull_request` run (`#41`) and automatically converged the PR body, host root traceability file, and session-local workspace copy. Provider-enabled agent execution validation now covers all currently enabled issue-comment tokens: `bounded_code_change` (`PR #24`, run `#45`), `documentation_update` (`PR #25`, run `#46`), `review_follow_up` (`PR #26`, run `#47`), and `ci_failure_investigation` (`PR #27`, run `#48`). No active near-term testing gap currently remains in the CLI proposal/traceability or provider-enabled adapter path; the main remaining follow-up is the separate operator-facing artifact-browsing improvement tracked in the issue workflow.

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
