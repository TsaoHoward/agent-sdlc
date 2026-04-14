# ADR-0004: Decision Document Workflow as a Durable Collaboration Surface

- Status: Accepted
- Date: 2026-04-14

## Context
The repository already treats docs as durable project memory, but unresolved decisions can still drift into transient chat context if there is no standardized place and workflow for capturing them.

For an AI-assisted SDLC workflow, this creates avoidable problems:
- humans cannot reliably see the current decision state without reading chat history
- AI agents may rediscover the same uncertainty repeatedly
- decision rationale, options, and next actions become fragmented across sessions
- the project loses a simple dashboard-like view of what is blocked, decided, or waiting for review

The project needs a durable decision-management workflow that works for both humans and AI agents.

## Decision
The repository will standardize on a decision-document workflow with these rules:

1. `docs/decisions/decision-backlog.md` is the durable dashboard for active near-term major decision items.
2. New or changed decision items should be added or updated in repository docs, not only described in chat.
3. Only major decisions should enter the active decision backlog.
4. Detail decisions may be implemented and documented in supporting design notes or implementation notes without occupying the active dashboard.
5. Each decision item should follow a standard structure and status model.
6. When a decision changes architecture, source-of-truth ownership, runtime isolation assumptions, CI ownership, deploy ownership, or cross-cutting governance, it must be promoted to an ADR.
7. Promoted or fully closed items should be moved out of the active decision backlog so the dashboard remains concise.
8. AI agents should update the decision backlog as part of normal work when they encounter unresolved major decisions, newly narrowed major options, or selected major directions.
9. When a major or detail decision is selected in a backlog item or supporting note, the same change set must update every directly affected architecture, policy, roadmap, WBS, or supporting design document so stale open questions do not remain as if the decision were still unresolved.
10. If a previously listed open question remains intentionally unresolved after a related document is updated, that document must explicitly narrow or restate the question rather than silently leaving the older wording in place.

## Decision Classification Rule

### Major Decision
A decision belongs in the active backlog when it materially does one or more of the following:
- blocks or meaningfully gates implementation progress
- affects architecture boundaries or durable ownership
- affects governance, policy, security posture, runtime assumptions, CI ownership, or deploy ownership
- materially changes whether a feature or workflow can be implemented, or how it fundamentally works
- requires explicit human selection among consequential directions

### Detail Decision
A decision should usually stay out of the active backlog when it is primarily:
- a field-level or syntax-level refinement inside an already chosen approach
- an implementation-facing parameter choice
- a naming, formatting, or low-level validation detail
- a detail that can be safely documented and revisited later without blocking major progress

Detail decisions should still be documented, but in supporting design docs rather than the dashboard.

## Rationale

### Why a Backlog Document
- gives humans and AI a shared current-state view
- reduces duplication across chat sessions
- supports a dashboard-like experience inside the repo

### Why Move-Out Is Required
- prevents the dashboard from becoming a permanent dumping ground
- keeps attention on active or near-term choices
- lets ADRs and archival references own resolved history

### Why Classification Is Required
- prevents low-level detail from flooding the dashboard
- keeps the backlog useful as an operator-facing overview
- lets humans and AI distinguish between true blockers and normal design elaboration

### Why Standardized Status and Structure
- keeps decision progress legible
- makes handoff easier
- prevents each agent run from inventing its own decision format

### Why Synchronized Write-Back Is Required
- prevents supporting notes from drifting away from architecture or planning docs
- keeps backlog and source docs aligned on what is still actually unresolved
- reduces false blockers caused by stale open-question lists

### Why Promote Some Decisions to ADRs
- preserves the distinction between pending choices and accepted durable decisions
- avoids treating a backlog entry as equivalent to a ratified architectural decision

## Consequences

### Positive
- simpler AI/human collaboration flow
- better visibility into blocked or pending items
- stronger durable project memory
- lower risk that design notes and planning docs drift out of sync

### Negative
- more discipline is required during planning and implementation
- some small decisions may feel heavier because they must be written down

## Follow-Up
This ADR should be supported by:
- a decision-management policy
- a decision backlog template
- a move-out surface for promoted or closed items
- updates to agent instructions and operating guidance
