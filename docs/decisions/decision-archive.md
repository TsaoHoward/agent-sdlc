# Decision Archive

## Document Metadata
- Version: 0.1
- Status: Active
- Last Updated: 2026-04-14
- Owner: Project Maintainer

## Purpose
This document records decision items that were intentionally moved out of `docs/decisions/decision-backlog.md`.

Use it to preserve a lightweight history when:
- a backlog item is promoted to an ADR
- a backlog item is closed and no longer needs dashboard visibility

This is not a substitute for ADRs. It is only the move-out surface for items that should no longer occupy space in the active dashboard.

## Archived Items
| Decision ID | Title | Outcome | Durable Reference | Moved Out On | Notes |
|---|---|---|---|---|---|
| D-001 | First Gitea Trigger Path | Closed | `docs/architecture/task-intake-contract.md` | 2026-04-14 | Top-level trigger family chosen; remaining details moved to D-007. |
| D-005 | Runtime Network And Secret Defaults | Promoted To ADR | `ADR-0003` | 2026-04-14 | Kept out of the active dashboard after ADR promotion. |
| D-007 | Gitea Issue Comment Command Design | Closed | `docs/decisions/D-007-gitea-issue-comment-command-design.md` | 2026-04-14 | Command pattern, authorization stance, and bounded-summary approach chosen; remaining field-level details moved to D-008. |
| D-008 | Command Token And Input Bounds | Moved Out As Detail Note | `docs/decisions/D-008-command-token-and-input-bounds.md` | 2026-04-14 | Field-level command details kept as a supporting note rather than an active major decision item. |

## Change Log
- 2026-04-14: Initial version.
