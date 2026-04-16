# Issue Dashboard

## Document Metadata
- Version: 0.1
- Status: Active
- Last Updated: 2026-04-16
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
| I-001 | Phase 1 Minimum Closed Loop Implementation Packaging | In Progress | `docs/roadmap.md` Phase 1; WBS `3`, `3.1`-`3.6` | Extend the new CI linkage into longer-lived traceability and review surfaces, and investigate artifact listing visibility only if operator-facing browsing becomes necessary | Archive after the first slice is underway and the remaining work is split or absorbed into active execution tracking |

## Issue Items

### I-001 - Phase 1 Minimum Closed Loop Implementation Packaging
- Status: `In Progress`
- Related Docs / WBS: `docs/roadmap.md` Phase 1; `docs/wbs.md` WBS `3`, `3.1`, `3.2`, `3.3`, `3.4`, `3.5`, `3.6`
- Why It Matters: The repository has completed the planning and design baseline for the first closed loop, but the implementation path still needs durable packaging into executable slices so work can leave the planning-only state.
- Current State: Task-intake, policy, runtime, PR/CI, and traceability contracts are documented, and `config/policy/` scaffolding exists. The repo now also has a project-local environment bootstrap entrypoint plus a repo-owned Gitea bootstrap config that uses explicit high-port forwarding and non-interactive PostgreSQL-backed forge initialization by default, and the bootstrap password-refresh path now preserves the tracked admin `mustChangePassword` setting so manual sign-in does not fall into an unstable forced password-change flow. The current implementation slice now includes a webhook-backed task gateway that retains source-event evidence under `.agent-sdlc/state/source-events/`, writes normalized task requests under `.agent-sdlc/state/task-requests/`, and auto-starts the direct session starter for auto-approved issue-comment commands. ADR-0006 has now been applied to the repo in four concrete ways: an npm-managed control-plane baseline exists via `package.json`, `package-lock.json`, and `tsconfig.json`; the first worker-runtime Dockerfile exists at `docker/worker-runtime/Dockerfile` and has been built locally as `agent-sdlc-worker-runtime:test`; `agent-control start-session` now launches that image to prepare a per-session workspace and runtime artifacts under `.agent-sdlc/runtime/`; `proposal-surface create-gitea-pr` now turns that prepared workspace into a real Gitea branch/PR proposal while writing the first linked traceability artifact into the proposal branch; and the first PR-triggered CI workflow now runs on the local Gitea Actions stack, generating verification linkage in `.agent-sdlc/ci/verification-metadata.json`, job logs, step summaries, and a persisted artifact in the local forge storage path after validation run `#19`. The remaining near-term gap is to push that CI linkage farther into durable traceability and review surfaces; artifact browsing through the local Gitea listing surface is a narrower follow-up if operator UX requires it.
- Next Action: Extend the new CI linkage into longer-lived traceability and review surfaces, and investigate artifact listing visibility only if operator-facing browsing becomes necessary.
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
- 2026-04-15: Updated I-001 after implementing the npm-managed control-plane baseline and the first worker-runtime Dockerfile scaffold.
- 2026-04-15: Updated I-001 after landing webhook-backed task intake, retained source-event records, and per-session worker-runtime handoff.
- 2026-04-16: Updated I-001 after landing the first branch/PR proposal path and proposal-linked traceability artifact.
- 2026-04-16: Updated I-001 after landing the first PR-triggered CI workflow, local Gitea runner helper, and verification-metadata linkage.
