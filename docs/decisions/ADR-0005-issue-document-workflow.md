# ADR-0005: Issue Document Workflow as a Durable Collaboration Surface

- Status: Accepted
- Date: 2026-04-15

## Context
The repository already has durable planning and decision-management surfaces, including roadmap, WBS, ADRs, and a decision backlog.

Even with those documents, active project issues can still drift into transient chat context when they are:
- active blockers or execution gaps
- cross-cutting follow-up items that span multiple docs or WBS entries
- work-packaging notes that are too detailed for roadmap/WBS but too important to leave only in chat
- handoff context that future agents or humans need in order to continue work safely

The project needs a durable issue-management workflow that:
- keeps active issue state reviewable in the repository
- adds move-out and supporting-note mechanisms so the dashboard stays concise
- does not replace the forge issue tracker, roadmap/WBS, decision backlog, or ADRs

## Decision
The repository will standardize on an issue-document workflow with these rules:

1. `docs/issues/issue-dashboard.md` is the durable dashboard for active near-term project issues that deserve repository-level visibility.
2. Complex issue context may be documented in supporting notes under `docs/issues/items/`.
3. Items that are done, closed, or no longer near-term move out of the active dashboard into `docs/issues/issue-archive.md` when a lightweight history entry is still useful.
4. The issue dashboard does not replace the forge as the canonical issue/comment/review history surface.
5. The issue dashboard does not replace `docs/roadmap.md`, `docs/wbs.md`, `docs/decisions/decision-backlog.md`, or ADRs.
6. Each active issue should record its next action and intended exit path.
7. AI agents should update the issue dashboard as part of normal work when active issue state materially changes.
8. When an issue changes planning, decision, or governance state, the related roadmap, WBS, decision backlog, or ADR documents must be updated in the same maintenance pass.

## Decision Details

### 1. Role Of The Issue Dashboard
The issue dashboard is the durable current-state and handoff surface for meaningful project issues.

It is intended to answer:
- what is active right now
- what is blocked or needs follow-up
- what should happen next
- how the item should leave the active dashboard later

### 2. Role Of Supporting Issue Notes
Supporting notes under `docs/issues/items/` hold deeper context when the dashboard should stay brief.

They may include:
- dependency breakdowns
- evidence and background
- work packaging detail
- cross-run handoff context
- implementation or analysis summaries

### 3. Relationship To Other Durable Surfaces
- the forge remains the canonical collaboration surface for issue, comment, PR, and review history
- roadmap and WBS remain the planning and sequencing structure
- the decision backlog remains the durable dashboard for major unresolved decisions
- ADRs remain the accepted architecture and governance decision surface

The issue workflow complements these surfaces rather than redefining their ownership.

## Rationale

### Why Not Rely On WBS Alone
WBS is the structural planning surface, but it is intentionally compact and not optimized for active blocker tracking or cross-run handoff notes.

### Why Not Rely On Forge Issues Alone
The forge is the canonical collaboration surface, but active issue synthesis still needs a durable repository-local view that future agent runs will read automatically as project memory.

### Why Move-Out Is Required
Without a move-out rule, the dashboard becomes a stale ledger instead of a current-state tool.

### Why Supporting Notes Are Required
Without supporting notes, the dashboard either becomes too shallow to help or too large to scan.

## Consequences

### Positive
- better continuity across human and agent runs
- clearer visibility into active blockers and next actions
- less pressure to overload WBS or decision docs with issue-tracking detail
- a durable exit-path workflow for current-state issue management

### Negative
- another document surface must be maintained
- humans and agents need discipline to avoid duplicating forge issues or WBS content

## Follow-Up
This ADR should be supported by:
- an issue-management policy
- an issue dashboard template
- an issue-note template
- an issue archive document
- updates to agent instructions, prompts, roadmap, and WBS references
