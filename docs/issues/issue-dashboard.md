# Issue Dashboard

## Document Metadata
- Version: 0.1
- Status: Active
- Last Updated: 2026-04-15
- Owner: Project Maintainer
- Source Template: docs/templates/issue-dashboard.template.md

## Purpose
This document is the durable dashboard for active near-term project issues that deserve repository-level visibility.

It does not replace forge issues, roadmap/WBS planning structure, the decision backlog, or ADRs. It is the current-state and handoff surface for meaningful project issues that would otherwise drift into chat or scattered notes.

## Issue Classification
- include only active or near-term issues that materially affect execution, coordination, blockers, or cross-run handoff
- keep complex issue detail in supporting notes under `docs/issues/items/`
- do not mirror every forge issue, comment thread, or small implementation task here

## Status Model
- `Open`
- `In Progress`
- `Blocked`
- `Ready For Review`
- `Deferred`
- `Done`
- `Closed`

## Move-Out Rule
- keep only active or near-term items in this document
- move `Done` or `Closed` items out at the next document maintenance pass
- move `Deferred` items out when they are no longer near-term
- record moved-out items in `docs/issues/issue-archive.md` when a lightweight history entry is still useful

## Supporting-Note Rule
- create a supporting issue note under `docs/issues/items/` when background, dependency, evidence, or handoff context no longer fits cleanly in the dashboard
- keep the dashboard concise even when a supporting note exists

## Exit And Promotion Rule
- every active issue item should record its intended exit path
- update roadmap and WBS when an issue changes work structure, scope, sequencing, or dependencies
- update `docs/decisions/decision-backlog.md` when an issue reveals a major unresolved decision
- create or update an ADR when an issue changes architecture, source-of-truth ownership, or cross-cutting governance

## Dashboard
| Issue ID | Title | Status | Related Docs / WBS | Next Action | Exit Path |
|---|---|---|---|---|---|
| I-001 | Phase 1 Minimum Closed Loop Implementation Packaging | In Progress | `docs/roadmap.md` Phase 1; WBS `3`, `3.1`-`3.6` | Add the selected platform-stack baseline to the repo by introducing npm-managed control-plane packaging and the first worker-runtime Dockerfile | Archive after the first slice is underway and the remaining work is split or absorbed into active execution tracking |

## Issue Items

### I-001 - Phase 1 Minimum Closed Loop Implementation Packaging
- Status: `In Progress`
- Related Docs / WBS: `docs/roadmap.md` Phase 1; `docs/wbs.md` WBS `3`, `3.1`, `3.2`, `3.3`, `3.4`, `3.5`, `3.6`
- Why It Matters: The repository has completed the planning and design baseline for the first closed loop, but the implementation path still needs durable packaging into executable slices so work can leave the planning-only state.
- Current State: Task-intake, policy, runtime, PR/CI, and traceability contracts are documented, and `config/policy/` scaffolding exists. The repo now also has a project-local environment bootstrap entrypoint plus a repo-owned Gitea bootstrap config that uses explicit high-port forwarding and non-interactive PostgreSQL-backed forge initialization by default, and the bootstrap password-refresh path now preserves the tracked admin `mustChangePassword` setting so manual sign-in does not fall into an unstable forced password-change flow. The first bounded implementation slice is now underway: repo-local task-gateway and agent-control CLIs can normalize a file-backed Gitea issue-comment command into `.agent-sdlc/state/task-requests/<task_request_id>.json` and create a pending session record under `.agent-sdlc/state/agent-sessions/<agent_session_id>.json`. The repo has now also selected a durable platform-stack baseline in ADR-0006: TypeScript/Node.js plus npm for the platform core, repo-owned Dockerfiles for control-plane and worker packaging, and later compose consolidation once the topology is stable. The repo still lacks actual webhook intake wiring, npm-managed control-plane packaging, worker runtime handoff, PR path, CI workflow, and end-to-end traceability implementation.
- Next Action: Apply ADR-0006 by introducing npm-managed control-plane packaging and the first worker-runtime Dockerfile, then continue from the current file-based intake/session scaffolds into webhook wiring and runtime handoff.
- Exit Path: Move this item to `docs/issues/issue-archive.md` once the first implementation slice is underway and the remaining work has been split into active execution issues or otherwise reflected in updated planning docs.
- Supporting Notes: `docs/issues/items/I-001-phase1-minimum-closed-loop-implementation.md`
- Promotion / Escalation Check: Update `docs/decisions/decision-backlog.md` and ADRs only if implementation uncovers a new major boundary, ownership, or governance decision.
- Notes: This item seeds the issue workflow with the project's current highest-signal active issue after the Phase 0 and Phase 1 design baseline.

## Change Log
- 2026-04-15: Initial version.
- 2026-04-15: Seeded I-001 to track the current Phase 1 implementation packaging gap.
- 2026-04-15: Marked I-001 in progress after adding the initial project-local environment bootstrap scaffold.
- 2026-04-15: Updated I-001 to reflect repo-owned bootstrap config, explicit forwarded ports, and non-interactive local Gitea installation.
- 2026-04-15: Recorded the admin-password refresh fix that keeps manual Gitea sign-in from re-entering the forced password-change flow.
- 2026-04-15: Updated I-001 after landing the first task-intake normalization and file-backed session-start scaffolds.
- 2026-04-15: Updated I-001 after selecting the platform implementation-stack and packaging baseline in ADR-0006.
