# I-001: Phase 1 Minimum Closed Loop Implementation

## Metadata
- Issue ID: I-001
- Status: In Progress
- Last Updated: 2026-04-15
- Owner: Project Maintainer
- Related Docs / WBS: `docs/roadmap.md` Phase 1; `docs/wbs.md` WBS `3`, `3.1`, `3.2`, `3.3`, `3.4`, `3.5`, `3.6`
- Source Dashboard: docs/issues/issue-dashboard.md
- Source Template: docs/templates/issue-note.template.md

## Summary
The project has completed its minimum closed-loop design baseline, but the implementation work is still concentrated in WBS 3 as not-started items. This note captures the recommended packaging of that work so future runs can pick up execution without rediscovering the same context.

## Why It Matters
The repository is intentionally still in an early-phase, structure-first posture. Without a durable packaging note, Phase 1 implementation can fragment into ad hoc coding or repeatedly restart from design review instead of moving through bounded implementation slices.

## Current State
- Phase 0 baseline items are complete, including roadmap, WBS, architecture, policy, environment baseline, and prompts.
- Phase 1 design items are complete, including task intake, runtime isolation, agent control integration, PR/CI path, and lifecycle traceability contracts.
- Machine-readable policy scaffolding exists under `config/policy/`.
- A project-local bootstrap entrypoint now exists to initialize `.agent-sdlc/` state paths and start the current local Gitea development forge from the repository, with repo-owned bootstrap settings, explicit high-port forwarding, PostgreSQL-backed startup as the default local path, SQLite as a fallback, and admin-password refresh behavior that preserves the tracked forced-password-change setting.
- A first bounded implementation slice now exists:
  - `node scripts/task-gateway.js normalize-gitea-issue-comment --event <path>` can parse the selected `@agent run <token>` contract against `config/policy/*.yaml` and persist normalized task requests under `.agent-sdlc/state/task-requests/`.
  - `node scripts/agent-control.js start-session --task-request <path>` can create pending session records under `.agent-sdlc/state/agent-sessions/` for auto-approved task requests.
  - the current control-host implementation uses repo-local Node.js CLIs as the first slice on the selected platform-stack convergence path rather than as a new architecture boundary by itself.
- The platform stack is now selected in ADR-0006:
  - the platform core should converge on `TypeScript` / `Node.js LTS` with `npm`
  - repo-owned Dockerfiles should package the control-plane and worker runtime before later compose consolidation
  - PowerShell remains acceptable for local operator wrappers without becoming the main control-plane implementation language
- The repo still lacks actual webhook delivery into the task gateway, worker runtime handoff, proposal path, CI workflow, and end-to-end traceability implementation.

## Dependencies And Constraints
- Work should stay aligned to Phase 1 and WBS 3 rather than pulling Phase 2 observability or multi-source scope forward.
- Implementation should preserve the existing layer boundaries between task gateway, policy, agent control, runtime, CI, and deploy.
- New architecture or governance shifts discovered during implementation should be escalated through the decision backlog and ADR flow rather than buried in code.
- Environment dependencies do not all need to be packaged inside the repository yet, but the active development stack should remain startable from repository-owned entrypoints so later consolidation into `docker compose` or an equivalent launcher stays possible.

## Proposed Handling Or Work Packaging
1. Start with the smallest intake-and-state slice:
   define the normalized task-request persistence path under `.agent-sdlc/state/task-requests/` and the trigger-adapter scaffold that can parse the selected issue-comment command contract.
2. Add the direct session-start boundary:
   implement the `agent-control start-session --task-request <path>` entry point and the file-backed session record under `.agent-sdlc/state/agent-sessions/`.
3. Stand up the isolated worker scaffold:
   prepare the ephemeral container runner interface and session-local workspace initialization needed by the runtime boundary.
4. Add proposal surfacing:
   implement branch naming, PR body traceability block, and `.agent-sdlc/traceability/<task_request_id>.json` creation.
5. Attach CI and lifecycle linkage:
   create the PR-triggered CI skeleton and carry `task_request_id` / proposal references through proposal and verification surfaces.

Steps 1 and 2 are now in progress with working file-backed CLI scaffolds. ADR-0006 now narrows the next packaging boundary further:
- first bring the growing platform code under the selected npm-managed stack
- then convert the pending session-start placeholder into real runtime handoff
- and do that without collapsing task gateway, agent control, and worker responsibilities together

## Exit Path
This issue exits the active dashboard when the first implementation slice is underway and the remaining implementation work has either:
- been split into more focused active issue items, or
- been sufficiently reflected in WBS and implementation scaffolding that this packaging note is no longer the primary handoff surface.

If implementation uncovers a major unresolved decision, the issue should stay active until the decision is captured in `docs/decisions/decision-backlog.md` and, if needed, promoted to an ADR.

## Next Actions
- add the first repo-owned Node package baseline for platform code and use it as the home for the control-plane growth path
- add the first worker-runtime Dockerfile so WBS `3.3` has a concrete packaging boundary
- replace the current file-based event input with actual webhook or equivalent adapter delivery into the task gateway path
- turn the pending-only session starter placeholder into a runtime handoff path for the worker scaffold
- expand the current project-local bootstrap entrypoints as those WBS 3 interfaces become real services or commands
- split or reframe this dashboard item once the implementation slices are concrete enough to track separately

## Change Log
- 2026-04-15: Initial version.
- 2026-04-15: Marked the issue in progress after adding the initial project-local environment bootstrap scaffold.
- 2026-04-15: Expanded the local forge bootstrap scaffold to include a PostgreSQL-backed default path and Docker Desktop auto-start handling.
- 2026-04-15: Added repo-owned bootstrap config and non-interactive local Gitea installation behavior.
- 2026-04-15: Verified the local bootstrap against a clean Gitea/PostgreSQL data set with automated admin-user creation and sign-in-page readiness.
- 2026-04-15: Captured the bootstrap fix that reapplies the tracked admin `mustChangePassword` setting during password refresh for existing data sets.
- 2026-04-15: Recorded the first working task-intake normalization and pending session-start CLI scaffolds for WBS 3.1 and 3.2.
- 2026-04-15: Added the selected platform-stack and packaging baseline after promoting it to ADR-0006.
