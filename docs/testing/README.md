# Testing Workflow

## Document Metadata
- Version: 0.1
- Status: Active
- Last Updated: 2026-04-21
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
4. run `TC-003` when you need the full operator-facing GUI path
5. write any new gap back into `docs/testing/test-dashboard.md`, then update issue or decision docs if the result changes project-level understanding

The latest reproducible live issue-comment reference is the 2026-04-21 run on `howard/agent-sdlc#11`, which created task request `trq-bd85673302e7`, session `ags-335855297620`, root traceability `.agent-sdlc/traceability/trq-bd85673302e7.json`, and proposal `PR #12` automatically after the strengthened listener path was deployed. The latest CLI half-live verification after commit `e97f0ba` then created synthetic task request `trq-route1-postfix-20260421111452`, session `ags-b927440ffcdd`, and proposal `PR #18`, which produced one successful `pull_request` run (`#37`) without the earlier duplicate sync-triggered second run. The current remaining near-term gap is still host-side canonical traceability refresh after CI success: the PR body converges automatically, but the host root traceability file can still wait for a later host-side sync event.

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

## Write-In And Move-Out Rule
- write active or newly discovered testing work into `docs/testing/test-dashboard.md`
- keep durable procedures in `docs/testing/items/`
- move `Passed`, `Deferred`, or `Retired` items out of the active dashboard when they no longer need attention
- record the move-out in `docs/testing/test-archive.md` when lightweight historical context is still useful

See `docs/policies/testing-management.md` for the full governance rule set.

## Change Log
- 2026-04-21: Initial version.
