# Decision Backlog

## Document Metadata
- Version: 0.2
- Status: Active
- Last Updated: 2026-04-14
- Owner: Project Maintainer
- Source Template: docs/templates/decision-backlog.template.md

## Purpose
This document is the durable dashboard for near-term decision items.

It is not an ADR. It tracks active, narrowed, recently selected, and deferred decisions so humans and AI agents can understand project state without relying on chat history.

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

## Dashboard
| Decision ID | Title | Status | Related Docs / WBS | Next Action |
|---|---|---|---|---|
| D-001 | First Gitea Trigger Path | Decided | WBS 3.1, task-intake-contract | define exact issue comment command syntax |
| D-002 | Minimum Machine-Readable Policy Schema | Decided | WBS 2.1, policy-representation | define exact field schema for first policy files |
| D-003 | Agent Control Integration Plan | Decided | WBS 2.2, agent-control-integration-plan | choose concrete session-starter interface shape |
| D-004 | PR And CI Path Definition | Decided | WBS 2.4, pr-and-ci-path-definition | define exact PR body and CI trigger conventions |
| D-006 | Traceability Display Strategy | Decided | WBS 2.5, lifecycle-traceability-contract | define exact PR traceability block and metadata artifact format |

## Decision Items

### D-001 — First Gitea Trigger Path
- Status: Decided
- Related Docs / WBS: WBS `3.1`, `docs/architecture/task-intake-contract.md`
- Why It Matters: It defines the first adapter entry point and the first human trigger surface.
- Background: The intake contract needs one explicit, auditable, low-ambiguity path for the first closed loop.
- Candidate Directions:
  Option A: issue comment command.
  Option B: issue label trigger.
  Option C: PR comment command.
- Selected Direction: Option A - `Gitea issue comment command`
- Remaining Detail Decisions:
  exact command form;
  membership/permission rule;
  whether free-form instructions are allowed.
- ADR Promotion Check: No, unless the trigger model changes ownership or routing assumptions.
- Notes: The source-normalized task contract must remain adapter-owned, not Gitea-payload-owned.

### D-002 — Minimum Machine-Readable Policy Schema
- Status: Decided
- Related Docs / WBS: WBS `2.1`, `docs/architecture/policy-representation.md`
- Why It Matters: It blocks policy lookup, execution-profile selection, and runtime capability resolution.
- Background: ADR-0002 selected repo docs plus `config/policy/`; the remaining question is the first executable schema shape.
- Candidate Directions:
  Option A: single policy file.
  Option B: split files by policy unit.
  Option C: hard-code first and externalize later.
- Selected Direction: Option B - split files by policy unit
- Remaining Detail Decisions:
  exact file layout;
  identifier naming convention;
  doc/config cross-reference method;
  per-file field schema.
- ADR Promotion Check: No, unless policy ownership or source of truth changes.
- Notes: The first practical layout is already hinted in `policy-representation.md`.

### D-003 — Agent Control Integration Plan
- Status: Decided
- Related Docs / WBS: WBS `2.2`, `docs/architecture/agent-control-integration-plan.md`
- Why It Matters: It defines the first boundary between task gateway and session startup.
- Background: Phase 1 needs a simple path that preserves the layer boundary without requiring a full queueing system first.
- Candidate Directions:
  Option A: direct session starter interface.
  Option B: queue-based control plane.
  Option C: embed launch inside task gateway.
- Selected Direction: Option A - direct session starter interface
- Remaining Detail Decisions:
  API versus CLI versus internal module boundary;
  first session record storage location;
  failure taxonomy.
- ADR Promotion Check: No, unless the task gateway starts owning control-plane responsibilities.
- Notes: The interface should remain abstract enough to move behind a queue later.

### D-004 — PR And CI Path Definition
- Status: Decided
- Related Docs / WBS: WBS `2.4`, `docs/architecture/pr-and-ci-path-definition.md`
- Why It Matters: It defines how the first review surface and independent verification surface appear.
- Background: Phase 1 needs the PR to exist as a normal human review surface while preserving CI independence.
- Candidate Directions:
  Option A: create branch and PR immediately.
  Option B: create branch first, PR after local checks.
  Option C: produce artifact first and let a human promote to PR.
- Selected Direction: Option A - create branch and PR immediately
- Remaining Detail Decisions:
  exact PR title/body convention;
  CI trigger timing;
  metadata artifact storage/reference pattern.
- ADR Promotion Check: No, unless CI ownership or review ownership changes.
- Notes: The PR body should remain readable while linking to fuller machine-readable metadata.

### D-006 — Traceability Display Strategy
- Status: Decided
- Related Docs / WBS: WBS `2.5`, `docs/architecture/lifecycle-traceability-contract.md`, `docs/architecture/pr-and-ci-path-definition.md`
- Why It Matters: It controls whether reviewers can understand provenance without digging through backend artifacts.
- Background: The traceability contract defined required identifiers, but reviewer-facing presentation was still open.
- Candidate Directions:
  Option A: PR body summary plus linked metadata artifact.
  Option B: structured comment only.
  Option C: artifact only.
- Selected Direction: Option A - PR body summary plus linked metadata artifact
- Remaining Detail Decisions:
  exact traceability block format;
  whether CI links appear in the same block;
  whether review decision references must be visible at merge time.
- ADR Promotion Check: No, unless traceability ownership shifts away from the repo/forge surfaces.
- Notes: The PR remains the human-readable review surface; the artifact carries fuller structured detail.

## Change Log
- 2026-04-14: Initial version.
- 2026-04-14: Standardized as a durable decision dashboard with status model, summary table, and structured decision items.
- 2026-04-14: Added move-out rule and removed ADR-promoted items from the active dashboard.
