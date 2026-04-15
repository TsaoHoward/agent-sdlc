# Decision Archive

## Document Metadata
- Version: 0.3
- Status: Active
- Last Updated: 2026-04-15
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
| D-002 | Minimum Machine-Readable Policy Schema | Closed | `docs/architecture/policy-representation.md` | 2026-04-14 | Exact Phase 1 file schema and doc/config ownership were written back into the architecture docs and config scaffolding. |
| D-003 | Agent Control Integration Plan | Closed | `docs/architecture/agent-control-integration-plan.md` | 2026-04-14 | Phase 1 starter boundary, record path, and failure taxonomy were made concrete in the control-plane design. |
| D-004 | PR And CI Path Definition | Closed | `docs/architecture/pr-and-ci-path-definition.md` | 2026-04-14 | PR conventions, CI trigger timing, and metadata artifact location were operationalized in the design docs. |
| D-006 | Traceability Display Strategy | Closed | `docs/architecture/lifecycle-traceability-contract.md` | 2026-04-14 | Reviewer-facing traceability block, metadata path, and retention defaults were written into the lifecycle contract. |
| D-009 | Issue Document Workflow | Promoted To ADR | `ADR-0005` | 2026-04-15 | Added a durable issue dashboard, archive, and supporting-note workflow without replacing forge issue ownership. |
| D-010 | Platform Implementation Stack And Packaging Baseline | Promoted To ADR | `ADR-0006` | 2026-04-15 | Selected TypeScript/Node.js plus npm as the platform core, kept docs/config multi-format by design, and set Dockerfile plus later compose packaging as the self-hosted path. |

## Change Log
- 2026-04-14: Initial version.
- 2026-04-14: Archived D-002, D-003, D-004, and D-006 after their selected defaults were synchronized into the architecture and planning docs.
- 2026-04-15: Archived D-009 after promoting the issue-document workflow choice to ADR-0005.
- 2026-04-15: Archived D-010 after promoting the platform implementation stack and packaging baseline to ADR-0006.
