# Decision Backlog

## Document Metadata
- Version: 0.4
- Status: Active
- Last Updated: 2026-04-15
- Owner: Project Maintainer
- Source Template: docs/templates/decision-backlog.template.md

## Purpose
This document is the durable dashboard for near-term major decision items.

It is not an ADR. It tracks active, narrowed, recently selected, and deferred major decisions so humans and AI agents can understand project state without relying on chat history.

## Decision Classification
- include only major decisions here
- keep detail decisions in supporting design or implementation notes
- a major decision is one that blocks progress, affects architecture/governance/ownership/security/runtime/CI/deploy assumptions, or materially changes feature/workflow implementation

## Status Model
- `Open`
- `In Analysis`
- `Ready For Review`
- `Decided`
- `Deferred`
- `Promoted To ADR`
- `Closed`

## Move-Out Rule
- keep only active or near-term items in this document
- move `Promoted To ADR` or `Closed` items out at the next document maintenance pass
- record moved-out items in `docs/decisions/decision-archive.md` when a lightweight history entry is still useful
- move detail-only items out when they no longer qualify as major dashboard items

## Dashboard
| Decision ID | Title | Status | Related Docs / WBS | Next Action |
|---|---|---|---|---|
No active major decision items currently require operator attention.

## Decision Items
No active major decision items are currently tracked here. Resolved major items were moved to `docs/decisions/decision-archive.md`, and remaining field-level defaults live in the supporting design notes and architecture docs.

## Change Log
- 2026-04-14: Initial version.
- 2026-04-14: Standardized as a durable decision dashboard with status model, summary table, and structured decision items.
- 2026-04-14: Added move-out rule and removed ADR-promoted items from the active dashboard.
- 2026-04-14: Moved the resolved top-level trigger-family item out of the active dashboard and added D-007 for the remaining command-design decision.
- 2026-04-14: Moved the decided D-007 trigger-design item out of the active dashboard and added D-008 for token and input-bound details.
- 2026-04-14: Narrowed the active dashboard to major decisions only and moved D-008 out as a supporting design note.
- 2026-04-14: Closed and moved out D-002, D-003, D-004, and D-006 after writing their selected defaults back into architecture and planning docs.
- 2026-04-15: Moved the issue-document workflow choice directly to ADR-0005 and kept the active dashboard empty because no unresolved major decision remains.
