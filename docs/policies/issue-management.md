# Issue Management Policy

## Purpose
This document defines how active project issues should be managed in repository documents.

It supports ADR-0005 and standardizes a durable collaboration workflow for humans and AI agents.

## 1. Core Rule
Active issue state that matters across sessions should live in repository documents, not only in chat or ad hoc notes.

Chat may summarize an issue or suggest next steps, but the repository is the durable issue-management surface.

## 2. Primary Issue Surfaces

### 2.1 Issue Dashboard
`docs/issues/issue-dashboard.md` is the primary dashboard for active near-term project issues that deserve durable repository visibility.

Use it for:
- active blockers or execution gaps
- cross-cutting follow-up items that span multiple docs or WBS entries
- issues that need durable handoff across agent runs
- near-term work-packaging gaps that are more specific than roadmap/WBS but do not justify becoming broad implementation notes

It should not become:
- a full mirror of every forge issue
- a replacement for `docs/wbs.md`
- a replacement for `docs/decisions/decision-backlog.md`
- a permanent historical ledger

### 2.1.1 Move-Out Rule
When a dashboard item reaches one of these states:
- `Done`
- `Closed`

it should be moved out of the active dashboard at the next document maintenance pass.

When a dashboard item is `Deferred`, it should also be moved out when it is no longer a near-term concern.

Move it to:
- `docs/issues/issue-archive.md` when a lightweight historical record is still useful
- the relevant WBS, supporting note, or implementation note when the dashboard no longer needs to carry it directly

### 2.1.2 Active Dashboard Rule
The dashboard table in `docs/issues/issue-dashboard.md` should show only active or near-term items that still deserve operator attention.

### 2.1.3 Classification Rule
Use the active issue dashboard only for issues that materially:
- affect execution, coordination, or handoff
- represent an active blocker, gap, inconsistency, or follow-up
- need explicit next actions or exit paths that should survive across runs

If an issue is detail-level or narrow enough to live only in implementation notes, keep it out of the dashboard.

### 2.1.4 Exit Path Rule
Every active issue should record an intended exit path, such as:
- move to archive after completion
- split into narrower active issues
- absorb into updated roadmap/WBS state
- escalate to the decision backlog or an ADR
- close as obsolete

### 2.2 Supporting Issue Notes
Use `docs/issues/items/` for supporting issue notes when an issue needs more detail than the dashboard should hold.

Supporting notes are the place for:
- background or evidence
- dependency breakdowns
- work packaging or sequencing detail
- cross-run handoff context
- implementation or analysis summaries that are too large for the dashboard

Not every dashboard item needs a supporting note.

### 2.3 Issue Archive
`docs/issues/issue-archive.md` is the move-out surface for issue items that no longer need active dashboard visibility.

### 2.4 Relationship To Other Durable Surfaces
- the forge remains the canonical source for issue, comment, PR, and review history
- `docs/roadmap.md` and `docs/wbs.md` remain the planning structure and sequencing source
- `docs/decisions/decision-backlog.md` remains the durable dashboard for major unresolved decisions
- ADRs remain the accepted architecture and governance decision surface
- the issue dashboard is the current-state and handoff surface that connects these without replacing them

## 3. Required Issue Item Fields
Each active dashboard item should include at least:
- issue title
- current status
- related docs or WBS references
- why the issue matters
- current state summary
- next action
- exit path
- supporting-note reference when one exists
- promotion or escalation guidance when roadmap/WBS, decision backlog, or ADR updates may be required

## 4. Standard Status Model
Use one of these statuses:
- `Open`
- `In Progress`
- `Blocked`
- `Ready For Review`
- `Deferred`
- `Done`
- `Closed`

`Done` and `Closed` are transition-end statuses and should usually trigger move-out from the active dashboard.

## 5. Agent Workflow Requirements
Before substantial work on an active issue, an AI agent should read any supporting issue note referenced by the dashboard item.

When an AI agent encounters a meaningful active issue, the agent should:
1. add or update the item in `docs/issues/issue-dashboard.md`
2. record the current state, next action, and exit path
3. create or update a supporting issue note when the dashboard summary is no longer sufficient
4. update roadmap, WBS, decision, or ADR docs in the same maintenance pass when the issue changes those surfaces

When an AI agent resolves or reframes an issue, the agent should:
1. update the dashboard item status
2. move the item out of the active dashboard when it no longer deserves operator attention
3. update `docs/issues/issue-archive.md` when a lightweight history record is still useful
4. leave an explicit note when related follow-up remains intentionally open

Do not leave meaningful active issue state only in chat if it affects future work.

## 6. Human Workflow Guidance
Humans may use the issue dashboard to:
- see what active issues or blockers still need attention
- understand the next recommended action
- recover cross-run handoff context quickly
- confirm whether an issue should remain a dashboard item, become a WBS change, or escalate into a decision or ADR

Humans may use supporting issue notes to inspect deeper context without bloating the dashboard.

## 7. Escalation Rules
Escalate an issue into roadmap or WBS updates when it changes:
- work structure
- sequencing
- dependencies
- milestone meaning or scope

Escalate an issue into the decision backlog when it reveals a major unresolved decision.

Escalate an issue into an ADR when it changes:
- architecture boundaries
- source-of-truth ownership
- runtime isolation assumptions
- CI or deploy ownership
- cross-cutting governance expectations

## 8. Dashboard Guidance
The issue dashboard should stay concise enough to scan quickly.

A useful dashboard view should let a reader answer:
- what is still active
- what is blocked
- what should happen next
- how each item is expected to leave the active dashboard

If the dashboard starts reading like a historical ledger, items should be moved out.
If the dashboard starts reading like implementation scratch notes, details should move into supporting issue notes instead.

## 9. Anti-Patterns
Do not:
- keep important active issue state only in chat
- mirror every forge issue in the dashboard
- use the dashboard as a replacement for WBS or ADRs
- leave dashboard items without an explicit exit path
- keep done or closed items in the active dashboard indefinitely
- let supporting issue notes drift away from the dashboard, roadmap, WBS, or decision docs they refine
