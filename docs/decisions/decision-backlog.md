# Decision Backlog

## Document Metadata
- Version: 0.5
- Status: Active
- Last Updated: 2026-04-23
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
| D-012 | Phase 1 Minimal Real Agent Execution Shape | Decided | `docs/roadmap.md` Phase 1; `docs/wbs.md` WBS `3.9` | Continue WBS `3.9` hardening from the validated DeepSeek path; move out at the next decision-maintenance pass if no new boundary decision appears |

## Decision Items
### D-012 - Phase 1 Minimal Real Agent Execution Shape
- Status: `Decided`
- Related Docs / WBS: `docs/roadmap.md` Phase 1; `docs/wbs.md` WBS `3.9`; `docs/architecture/agent-control-integration-plan.md`; `docs/architecture/runtime-isolation.md`
- Why It Matters: Phase 1 now explicitly requires one real provider-backed agent execution slice, but the repo should still avoid turning one model/provider/tool surface into a hidden architecture decision.
- Current State: The current Phase 1 loop reaches live intake, session startup, isolated runtime preparation, proposal PR creation, CI verification, and durable traceability. Task tokens currently influence classification and policy, and the selected D-012 direction is now implemented far enough to validate a provider-backed path: keep orchestration repo-owned, support both remote and local backends through a configuration-selected API adapter, and use `DeepSeek API` as the short-term remote default for the first WBS `3.9` slice. The 2026-04-23 provider-enabled smoke created task request `trq-4faac7e2a74b`, session `ags-cd9d3e289f02`, local PR `#24`, and DeepSeek-generated documentation with passing provider-requested validation.
- Next Action: Continue WBS `3.9` hardening from the validated DeepSeek path, keep the first execution loop bounded, and only promote to an ADR if implementation changes architecture boundaries, source-of-truth ownership, runtime isolation, or cross-cutting governance assumptions.
- Exit Path: Move this item out once WBS `3.9` is either narrowed into implementation-ready defaults in existing docs or promoted to an ADR because the decision changes cross-cutting architecture/governance assumptions.

## Change Log
- 2026-04-14: Initial version.
- 2026-04-14: Standardized as a durable decision dashboard with status model, summary table, and structured decision items.
- 2026-04-14: Added move-out rule and removed ADR-promoted items from the active dashboard.
- 2026-04-14: Moved the resolved top-level trigger-family item out of the active dashboard and added D-007 for the remaining command-design decision.
- 2026-04-14: Moved the decided D-007 trigger-design item out of the active dashboard and added D-008 for token and input-bound details.
- 2026-04-14: Narrowed the active dashboard to major decisions only and moved D-008 out as a supporting design note.
- 2026-04-14: Closed and moved out D-002, D-003, D-004, and D-006 after writing their selected defaults back into architecture and planning docs.
- 2026-04-15: Moved the issue-document workflow choice directly to ADR-0005 and kept the active dashboard empty because no unresolved major decision remains.
- 2026-04-15: Promoted the platform implementation stack and packaging baseline directly to ADR-0006 and kept the active dashboard empty because no unresolved major decision remains.
- 2026-04-21: Promoted the testing workflow choice directly to ADR-0007 and kept the active dashboard empty because no unresolved major decision remains.
- 2026-04-22: Added D-012 to track the still-open provider/tooling/context shape for the first real Phase 1 agent execution slice under WBS `3.9`.
- 2026-04-22: Moved D-012 to `In Analysis` and linked the new supporting note that narrows the first-slice recommendation toward repo-owned orchestration plus a provider-backed execution adapter.
- 2026-04-22: Marked D-012 `Decided` after selecting a config-switched remote/local-capable adapter direction with `DeepSeek API` as the short-term remote default.
- 2026-04-23: Renumbered the active execution-shape decision from D-009 to D-012 to avoid conflicting with archived D-009.
- 2026-04-23: Recorded the first implementation defaults for config path, DeepSeek model, project-local API key field, and execution evidence artifact.
- 2026-04-23: Promoted repository-wide configuration template and local-config handling directly to ADR-0008 and policy docs.
- 2026-04-23: Recorded provider-enabled DeepSeek validation through local PR `#24`; no new architecture-boundary decision was discovered.
