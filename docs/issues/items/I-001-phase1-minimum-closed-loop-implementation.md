# I-001: Phase 1 Minimum Closed Loop Implementation

## Metadata
- Issue ID: I-001
- Status: Open
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
- No implementation scaffold currently exists for the task gateway, agent-control starter, worker runtime, proposal path, CI workflow, or traceability files under `.agent-sdlc/`.

## Dependencies And Constraints
- Work should stay aligned to Phase 1 and WBS 3 rather than pulling Phase 2 observability or multi-source scope forward.
- Implementation should preserve the existing layer boundaries between task gateway, policy, agent control, runtime, CI, and deploy.
- New architecture or governance shifts discovered during implementation should be escalated through the decision backlog and ADR flow rather than buried in code.

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

## Exit Path
This issue exits the active dashboard when the first implementation slice is underway and the remaining implementation work has either:
- been split into more focused active issue items, or
- been sufficiently reflected in WBS and implementation scaffolding that this packaging note is no longer the primary handoff surface.

If implementation uncovers a major unresolved decision, the issue should stay active until the decision is captured in `docs/decisions/decision-backlog.md` and, if needed, promoted to an ADR.

## Next Actions
- choose the first concrete implementation slice inside WBS 3
- create the corresponding code or scaffold changes
- update `docs/issues/issue-dashboard.md` when the work shifts from packaging into active implementation

## Change Log
- 2026-04-15: Initial version.
