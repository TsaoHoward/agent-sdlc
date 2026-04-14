# Decision Management Policy

## Purpose
This document defines how pending, selected, deferred, and promoted decisions should be managed in repository documents.

It supports ADR-0004 and standardizes a durable collaboration workflow for humans and AI agents.

## 1. Core Rule
Decision context should live in repository documents, not only in chat.

Chat may summarize a decision or ask for input, but the repository is the durable collaboration surface.

## 2. Primary Decision Surfaces

### 2.1 Decision Backlog
`docs/decisions/decision-backlog.md` is the primary dashboard for near-term major decision items.

Use it for:
- open major decisions
- narrowed major decisions with candidate directions
- recently selected major decisions not yet promoted into ADRs or other durable docs
- deferred or blocked major decision items

It should not become a permanent historical ledger.

### 2.1.1 Move-Out Rule
When a backlog item reaches either of these states:
- `Promoted To ADR`
- `Closed`

it should be moved out of the active backlog at the next document maintenance pass.

Move it to:
- the relevant ADR, when ADR promotion is the durable outcome
- `docs/decisions/decision-archive.md`, when the item is closed and only a lightweight historical record is needed

### 2.1.2 Active Dashboard Rule
The dashboard table in `docs/decisions/decision-backlog.md` should show only active or near-term items that still deserve operator attention.

### 2.1.3 Classification Rule
Use the active decision backlog only for major decisions.

A decision is major when it materially:
- blocks implementation progress
- affects architecture, governance, ownership, security posture, runtime assumptions, CI, or deploy boundaries
- changes whether or how an important feature/workflow can be implemented
- needs explicit human choice among consequential alternatives

If a decision is detail-level rather than major, document it in a supporting design note or implementation note instead of the active dashboard.

### 2.2 ADRs
Use ADRs for accepted decisions that affect:
- architecture boundaries
- source-of-truth ownership
- runtime isolation assumptions
- CI or deploy ownership
- cross-cutting governance rules

### 2.3 Policies and Design Specs
When a decision is selected, related policies and design specs should be updated so the selected direction becomes operationally useful.

This write-back requirement also applies to:
- architecture specs that still describe the item as open
- roadmap or WBS open-question lists that still present the resolved item as unresolved
- supporting notes that should now carry the concrete selected defaults

## 3. Required Decision Item Fields
Each major decision item in the backlog should include at least:
- decision title
- current status
- why the decision matters
- current background or context
- candidate directions when still open
- selected direction when decided
- remaining detail decisions, if any
- promotion guidance when ADR review may be required

## 4. Standard Status Model
Use one of these statuses:
- `Open`
- `In Analysis`
- `Ready For Review`
- `Decided`
- `Deferred`
- `Promoted To ADR`
- `Closed`

`Promoted To ADR` and `Closed` are transition-end statuses and should usually trigger move-out from the active backlog.

## 5. Agent Workflow Requirements
When an AI agent encounters a meaningful unresolved major decision, the agent should:
1. add or update the item in `docs/decisions/decision-backlog.md`
2. record the relevant context, options, and recommendation
3. mark whether ADR promotion may be required
4. update related docs after the user selects a direction

When an AI agent encounters a detail decision, the agent should:
1. document it in the relevant supporting design note or implementation note
2. avoid promoting it into the active backlog unless it becomes major or blocking

When an AI agent records a selected direction in either a major-decision item or a detail note, the agent should:
1. update the directly affected architecture, policy, roadmap, WBS, and supporting design docs in the same maintenance pass
2. remove or narrow stale open-question bullets that the selected direction already resolved
3. move the decision out of the active backlog when it no longer deserves operator attention
4. leave an explicit note when a related question is intentionally still open

Do not leave meaningful major decision discovery only in chat if it affects future work.

## 6. Human Workflow Guidance
Humans may use the backlog as a dashboard to:
- see what is blocking implementation
- understand why a choice matters
- choose among candidate directions
- confirm what still needs a formal ADR

Humans may use supporting design notes to inspect lower-level decisions without expanding the dashboard.

## 7. Decision Promotion Rule
Promote a backlog item to an ADR when the selected direction changes:
- what the system is
- which layer owns a responsibility
- where durable truth lives
- runtime isolation assumptions
- who verifies or deploys
- cross-cutting governance expectations

## 8. Dashboard Guidance
The decision backlog should stay concise enough to scan quickly.

A useful dashboard view should let a reader answer:
- what is still open
- what was recently decided
- what is blocked
- what needs ADR promotion

If the dashboard starts reading like a historical ledger, items should be moved out.
If the dashboard starts reading like a design notebook, detail decisions should be moved out as well.

## 9. Anti-Patterns
Do not:
- keep important decision context only in chat
- treat backlog notes as implicit ADR approval
- leave decided directions unreflected in roadmap, WBS, policy, or design docs
- let supporting design notes quietly diverge from the architecture or planning docs they refine
- let the backlog become an unstructured scratchpad
- keep promoted or closed items in the active dashboard indefinitely
- put low-level detail decisions into the active dashboard when they do not materially affect progress or architecture
