# User Capability Matrix

## Document Metadata
- Version: 0.1
- Status: Active
- Last Updated: 2026-04-23
- Owner: Project Maintainer

## Purpose
This document is the durable current-state matrix for what a user can ask the system to do, where that request can be made, and how far the implemented Phase 1 workflow actually carries that request today.

It is intentionally tied to:
- the project vision in `docs/project-overview.md`
- the active implementation packaging issue in `docs/issues/issue-dashboard.md`
- the current Phase 1 plan in `docs/roadmap.md` and `docs/wbs.md`

Use it when you need one place to answer:
- where `@agent` is currently supported
- what `@agent run <token>` means right now
- which parts of the end-to-end lifecycle are automated versus still generic scaffold
- which manual operator commands exist alongside the live `@agent` path

## Linked Planning Context
- Project vision: `docs/project-overview.md`
- Active issue packaging: `docs/issues/issue-dashboard.md` item `I-001`
- Related roadmap phase: `docs/roadmap.md` Phase 1
- Related WBS items: `docs/wbs.md` WBS `3.1`, `3.2`, `3.3`, `3.4`, `3.5`, `3.6`, `3.7`, `3.8`

## Status Legend
- `Implemented`: a user-facing path exists and the documented lifecycle behavior is working in the current repo-owned flow
- `Implemented Scaffold`: the path is live and traceable end to end, but task-specific execution behavior is still generic rather than deeply specialized
- `Manual Operator Only`: the capability exists through repo-owned CLI or bootstrap commands, not through a live `@agent` user entrypoint
- `Not Supported`: the surface or request form is not currently wired into an executable path

## Project-Vision Link
The target top-level experience from `docs/project-overview.md` is:

`issue / comment / label -> task intake -> agent execution -> code proposal -> PR -> CI -> human review / merge`

The current Phase 1 implementation only exposes one live user trigger in that chain:
- `Gitea issue comment -> @agent run <token>`

This matrix therefore separates:
- the current live user-facing surface
- the current manual operator surfaces
- the source types that are described in architecture or policy but are not yet live

## Location Matrix
| User Location / Surface | Can the user type `@agent` here? | Current Behavior | Status | Related Docs |
|---|---|---|---|---|
| Gitea issue comment | Yes | Newly created issue comments are parsed by the task gateway, normalized into a task request, auto-started when auto-approved, and currently continue into session, proposal PR, CI, and traceability flow | Implemented | `docs/architecture/task-intake-contract.md`, `docs/testing/items/TC-003-gui-full-live-issue-comment-smoke.md` |
| Gitea issue body | No | No live intake path reads issue bodies for `@agent` commands | Not Supported | `docs/policies/task-intake.md` |
| Gitea PR comment | No | `pull_request_comment` exists as a planned source family in docs, but it is not currently wired as a live intake path | Not Supported | `docs/architecture/task-intake-contract.md` |
| Gitea PR review comment | No | Review events are consumed for traceability refresh, not for `@agent` task intake | Not Supported | `docs/environment-bootstrap.md`, `scripts/review-surface.js` |
| Gitea issue label | No | `issue_label` exists as a future source family in docs, but there is no live label-driven `@agent` path | Not Supported | `docs/architecture/task-intake-contract.md` |
| Manual CLI replay | Not applicable | Operators can replay file-backed events and advance lifecycle steps with repo-owned CLI commands | Manual Operator Only | `docs/testing/local-test-procedures.md`, `docs/environment-bootstrap.md` |
| PR close / reopen / review actions | Not applicable | These events can refresh review and traceability state, but they are not `@agent` entrypoints | Implemented | `docs/testing/local-test-procedures.md`, `scripts/review-surface.js` |

## Live `@agent` Intent Matrix
| User Intent | Command Form | Normalized Task Class | Summary Required | Current Automated Path | Current Practical Result | Status |
|---|---|---|---|---|---|---|
| Documentation update | `@agent run docs` | `documentation_update` | No | issue comment -> task request -> session start -> workspace prepare -> proposal PR -> CI -> reviewable traceability | The system routes and traces the request end to end, but the runtime still uses the common Phase 1 scaffold rather than a docs-specialized worker implementation | Implemented Scaffold |
| Bounded code change | `@agent run code` + `summary:` | `bounded_code_change` | Yes | issue comment -> task request -> session start -> workspace prepare -> optional configured agent execution -> proposal PR -> CI -> reviewable traceability | This is the main intended Phase 1 path. The request is classified, auto-started, proposed, verified, and surfaced for human review; the first template-backed DeepSeek adapter has now passed provider-enabled local validation but remains opt-in through ignored project config | Implemented Scaffold |
| Review follow-up | `@agent run review` | `review_follow_up` | No | issue comment -> task request -> session start -> workspace prepare -> proposal PR -> CI -> reviewable traceability | The request enters the same Phase 1 execution/proposal pipeline, but there is not yet a review-thread-specialized worker loop | Implemented Scaffold |
| CI failure investigation | `@agent run ci` + `summary:` | `ci_failure_investigation` | Yes | issue comment -> task request -> session start -> workspace prepare -> proposal PR -> CI -> reviewable traceability | The request is classified into the investigation profile, but the current implementation still uses the common session/proposal scaffold instead of a distinct investigation-only user workflow | Implemented Scaffold |

## Manual Operator Capability Matrix
| Operator Capability | Entry Point | What It Is Used For | Status | Related Docs |
|---|---|---|---|---|
| Replay issue-comment intake from file | `node scripts/task-gateway.js normalize-gitea-issue-comment --event <path>` | deterministic local intake debugging without live Gitea delivery | Implemented | `docs/testing/items/TC-001-cli-replay-intake-and-session-smoke.md` |
| Run live issue-comment webhook listener | `node scripts/task-gateway.js serve-configured-gitea-webhook` | local control-host intake endpoint for Gitea issue-comment delivery, configured from template/local bootstrap config | Implemented | `docs/environment-bootstrap.md` |
| Start a session from a task request | `node scripts/agent-control.js start-session --task-request <path>` | direct session start from a normalized task request | Implemented | `docs/architecture/agent-control-integration-plan.md` |
| Auto-create proposal during session start | `node scripts/agent-control.js start-session --task-request <path> --auto-create-proposal` | current live issue-comment continuation path for auto-approved requests | Implemented | `docs/testing/local-test-procedures.md` |
| Create or refresh a proposal PR | `node scripts/proposal-surface.js create-gitea-pr --session <path>` | branch and PR proposal path from a prepared session workspace | Implemented | `docs/testing/items/TC-002-cli-proposal-and-traceability-smoke.md` |
| Sync review outcome from a proposal | `node scripts/review-surface.js sync-gitea-pr-review-outcome --proposal <proposal_ref>` | refresh durable review state and PR traceability after review activity | Implemented | `docs/environment-bootstrap.md` |
| Sync proposal traceability from a proposal | `node scripts/review-surface.js sync-gitea-proposal-traceability --proposal <proposal_ref>` | refresh canonical and session-local traceability copies for proposal/CI convergence or diagnostics | Implemented | `scripts/review-surface.js` |
| Run review-follow-up webhook listener | `node scripts/review-surface.js serve-configured-gitea-review-webhook` | accept PR review and PR state-change events for automatic traceability refresh, configured from template/local bootstrap config | Implemented | `docs/environment-bootstrap.md` |

## Current End-to-End User Flow
For the current live Phase 1 `@agent` path, the implemented lifecycle is:

1. A user posts a newly created Gitea issue comment using `@agent run <docs|code|review|ci>`.
2. The task gateway validates the bounded command contract and resolves task class, execution profile, runtime capability set, and approval state.
3. A normalized task request is written to `.agent-sdlc/state/task-requests/<task_request_id>.json`.
4. For auto-approved requests, agent control starts a session and writes `.agent-sdlc/state/agent-sessions/<agent_session_id>.json`.
5. The worker runtime prepares a session-local workspace under `.agent-sdlc/runtime/workspaces/`.
6. The proposal surface creates `agent/<task_request_id>` plus a Gitea PR and writes linked traceability metadata.
7. The PR-triggered CI workflow runs independently and writes verification metadata.
8. CI completion now syncs reviewer-facing PR traceability plus canonical and session-local traceability copies.
9. Human review remains the merge gate.
10. Later review, close, or reopen events can refresh review outcome traceability through the review surface.

## Evidence Surfaces By Stage
| Stage | Durable Evidence |
|---|---|
| User trigger accepted | `.agent-sdlc/state/source-events/`, `.agent-sdlc/state/task-requests/` |
| Session started | `.agent-sdlc/state/agent-sessions/`, `.agent-sdlc/runtime/artifacts/` |
| Proposal created | Gitea PR UI, `.agent-sdlc/traceability/<task_request_id>.json` |
| CI verified | Gitea Actions run, `.agent-sdlc/ci/verification-metadata.json`, PR traceability block |
| Review synced | PR body, root traceability file, session-local traceability copy |

## Current Boundaries And Gaps
- Only Gitea issue comments are currently live `@agent` entrypoints.
- The four task tokens currently drive classification, policy, and traceability. A first opt-in agent execution adapter exists for `bounded_code_change` and has passed provider-enabled local validation, but live default behavior remains scaffold-first unless the operator enables agent execution in ignored project config.
- CI remains an independent verifier and human review remains the merge control point.
- Operator-facing artifact browsing remains a narrower follow-up outside this matrix's core capability scope.

## Maintenance Rule
Update this document when any of the following change:
- supported `@agent` locations
- supported task tokens or parsing rules
- automatic versus manual lifecycle boundaries
- linked evidence surfaces
- issue, roadmap, or WBS references that describe the current user-facing capability shape

When a change is substantial enough to alter the supported workflow shape, also update:
- `docs/issues/issue-dashboard.md`
- `docs/issues/items/I-001-phase1-minimum-closed-loop-implementation.md` or its successor issue note
- `docs/roadmap.md`
- `docs/wbs.md`

## Change Log
- 2026-04-22: Initial version.
- 2026-04-23: Updated `bounded_code_change` coverage after landing the first opt-in config-selected agent execution adapter slice.
- 2026-04-23: Updated `bounded_code_change` coverage after provider-enabled DeepSeek validation produced a session-backed local proposal.
