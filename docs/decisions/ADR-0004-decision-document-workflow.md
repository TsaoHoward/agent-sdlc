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

1. `docs/decisions/decision-backlog.md` is the durable dashboard for active near-term decision items.
2. New or changed decision items should be added or updated in repository docs, not only described in chat.
3. Each decision item should follow a standard structure and status model.
4. When a decision changes architecture, source-of-truth ownership, runtime isolation assumptions, CI ownership, deploy ownership, or cross-cutting governance, it must be promoted to an ADR.
5. Promoted or fully closed items should be moved out of the active decision backlog so the dashboard remains concise.
6. AI agents should update the decision backlog as part of normal work when they encounter unresolved decisions, newly narrowed options, or selected directions.

## Rationale

### Why a Backlog Document
- gives humans and AI a shared current-state view
- reduces duplication across chat sessions
- supports a dashboard-like experience inside the repo

### Why Move-Out Is Required
- prevents the dashboard from becoming a permanent dumping ground
- keeps attention on active or near-term choices
- lets ADRs and archival references own resolved history

### Why Standardized Status and Structure
- keeps decision progress legible
- makes handoff easier
- prevents each agent run from inventing its own decision format

### Why Promote Some Decisions to ADRs
- preserves the distinction between pending choices and accepted durable decisions
- avoids treating a backlog entry as equivalent to a ratified architectural decision

## Consequences

### Positive
- simpler AI/human collaboration flow
- better visibility into blocked or pending items
- stronger durable project memory

### Negative
- more discipline is required during planning and implementation
- some small decisions may feel heavier because they must be written down

## Follow-Up
This ADR should be supported by:
- a decision-management policy
- a decision backlog template
- a move-out surface for promoted or closed items
- updates to agent instructions and operating guidance
