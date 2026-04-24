# Test Framework

## Document Metadata
- Version: 0.1
- Status: Active
- Last Updated: 2026-04-24
- Owner: Project Maintainer

## Purpose
This document defines how local testing is executed, observed, and written back into the repository's durable workflow surfaces.

It complements `docs/testing/test-plan.md` by describing the stable execution model rather than only the test scope.

## Framework Goals
- keep local testing repeatable across runs
- separate canonical procedures from current-cycle tracking
- make evidence expectations explicit for each lifecycle stage
- ensure failures are written back into issue, decision, and planning surfaces when needed

## Execution Modes

### Mode A - CLI Replay
Use when:
- you want to inspect one boundary in isolation
- live webhook delivery is not required
- you want the easiest reproduction path

Typical entry points:
- `node scripts/task-gateway.js normalize-gitea-issue-comment --event <path>`
- `node scripts/agent-control.js start-session --task-request <path>`

### Mode B - CLI Half-Live
Use when:
- you want to interact with the real local forge and proposal path
- you still want deterministic operator control over each step
- you want to inspect traceability or review-sync behavior without depending on a live issue-comment trigger

Typical entry points:
- `node scripts/proposal-surface.js create-gitea-pr --session <path>`
- `node scripts/review-surface.js sync-gitea-pr-review-outcome --proposal <proposal_ref>`

### Mode C - GUI Live
Use when:
- you want to validate the actual operator experience in local Gitea
- you need to observe live webhook behavior
- you want to confirm the end-to-end happy path rather than one isolated boundary

Typical entry points:
- create issue and comment in the local Gitea UI
- observe PR, Actions, review, close, and reopen behavior in the UI

### Mode D - External Target Evaluation
Use when:
- you need evidence about service behavior beyond the platform repo itself
- you want to observe bounded AI work on a non-platform target repo
- you need promotion evidence for later pilot claims

Typical entry points:
- provision or reset a controlled non-platform target repo
- run a bounded `@agent` path or replay flow against that target repo
- score the resulting PR, CI result, and edit boundary against a reusable rubric

## Observation Surfaces By Lifecycle Stage
| Lifecycle Stage | Primary Observation Surface | Secondary Evidence |
|---|---|---|
| bootstrap health | `manage-dev-environment.ps1 -Command status` | `.agent-sdlc/dev-env/gitea/bootstrap-summary.json` |
| issue-comment intake | task-gateway webhook log | `.agent-sdlc/state/source-events/`, `.agent-sdlc/state/task-requests/` |
| session start | session JSON and runtime artifacts | `agent-control` command output |
| runtime preparation | `.agent-sdlc/runtime/workspaces/` and `.agent-sdlc/runtime/artifacts/` | session record |
| proposal creation | Gitea PR UI and traceability JSON | `proposal-surface` command output |
| CI verification | Gitea Actions UI and traceability JSON | `.agent-sdlc/ci/verification-metadata.json` |
| review follow-up | review-surface webhook log and PR body | `.agent-sdlc/traceability/*.json`, `hook_task` rows when deep debugging is required |

## Canonical Case Convention
Canonical case notes under `docs/testing/items/` should:
- hold the exact operator steps
- include stable default data such as URLs, users, repo name, and command text
- describe expected evidence, not just commands
- include cleanup notes when stateful local artifacts or PRs are created

The active dashboard may reference these cases, but the case notes remain the source of truth for procedures.

## Active Dashboard Convention
`docs/testing/test-dashboard.md` tracks only active or near-term testing work.

## Evidence Classification Rule
Testing docs should classify evidence as one of:
- `platform self-test / platform regression`
- `external target service evaluation`

Runs against the seeded local `agent-sdlc` repo remain valid and useful, but they must not be treated as the only basis for broader pilot or production claims.

Use the dashboard to answer:
- which regression cases still need attention
- what is blocked right now
- what should be run next
- what can move out once the current validation window closes

Move out items when they are passed for the current cycle, deferred beyond the near term, or retired entirely.

## Failure Write-Back Rules
When a test fails:
- update `docs/testing/test-dashboard.md`
- update or create the canonical case note if the procedure or expectation itself changed
- update `docs/issues/issue-dashboard.md` when the failure is an active blocker or meaningful execution gap
- update `docs/decisions/decision-backlog.md` when the failure reveals a major unresolved decision
- update roadmap, WBS, policies, or ADRs in the same maintenance pass if the failure changes planning, governance, or architecture assumptions

## Stable Local Debug Aids
For deeper local debugging, the framework permits these evidence surfaces:
- control-host logs under `.agent-sdlc/dev-env/control-host/logs/`
- recent task/session/traceability JSON files under `.agent-sdlc/`
- local Gitea Actions UI and PR UI
- local Gitea `hook_task` rows when webhook delivery behavior needs confirmation

## Change Log
- 2026-04-21: Initial version.
- 2026-04-24: Added Mode D and the evidence-classification rule that separates platform regression from external target service evaluation.
