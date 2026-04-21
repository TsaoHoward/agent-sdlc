# ADR-0007: Testing Workflow as a Durable Collaboration Surface

- Status: Accepted
- Date: 2026-04-21

## Context
The repository already has durable planning, decision, issue, and implementation guidance surfaces, but local validation and end-to-end test knowledge still risks drifting into chat history, ad hoc shell transcripts, and one-off PR comments.

For the current Phase 1 closed-loop work, that creates avoidable problems:
- maintainers cannot reliably see which local validation paths are current, blocked, or already proven
- AI agents may re-discover the same manual test steps, credentials, or evidence paths in each run
- CLI replay, GUI walkthrough, and live webhook validation procedures can diverge without a stable write-in and move-out workflow
- evidence about what still needs manual validation can remain trapped in issue notes instead of becoming a reusable testing workflow

The project needs a durable testing workflow that:
- keeps stable local test procedures in the repository
- tracks active near-term validation work without turning the dashboard into a permanent ledger
- preserves canonical test cases separately from the current-cycle tracking view
- complements, rather than replaces, CI, forge history, issue dashboards, or ADRs

## Decision
The repository will standardize on a testing-document workflow with these rules:

1. `docs/testing/test-plan.md` defines the stable testing scope, environments, entry criteria, exit criteria, and default local test data.
2. `docs/testing/test-framework.md` defines the repeatable testing model, execution modes, evidence surfaces, and failure/write-back rules.
3. `docs/testing/test-dashboard.md` is the durable dashboard for active near-term testing work that still deserves operator attention.
4. Canonical test procedures and case definitions live under `docs/testing/items/`.
5. Items that are passed for the current validation window, deferred beyond the near term, or retired move out of the active dashboard into `docs/testing/test-archive.md` when a lightweight history entry is still useful.
6. The testing workflow does not replace CI as the independent verifier, the forge as the canonical collaboration surface, or roadmap/WBS/issue/decision docs as the planning and governance surfaces.
7. AI agents should update the testing plan, framework, dashboard, archive, and case notes as part of normal work when test procedures, active validation state, or evidence expectations materially change.
8. When testing work changes planning, governance, or architecture assumptions, the related roadmap, WBS, issue, decision, policy, or ADR documents must be updated in the same maintenance pass.

## Decision Details

### 1. Role Of The Test Plan
The test plan is the stable operator-facing view of:
- what must be tested
- which environments and modes exist
- what entry and exit criteria define a useful validation pass
- which default local credentials, repo names, ports, and paths are expected

### 2. Role Of The Test Framework
The test framework turns the plan into a repeatable operating model by defining:
- CLI replay versus half-live versus full-live validation modes
- what evidence each lifecycle stage should produce
- how failures should be written back into dashboard, issue, and decision surfaces
- how current-cycle tracking differs from canonical long-lived test cases

### 3. Role Of The Test Dashboard
The test dashboard is the active current-state surface for:
- near-term validation gaps
- currently watched regression cases
- blocked or failed manual verification items
- the next recommended test action for the current slice

It is not the place to store every historical pass forever.

### 4. Role Of Canonical Test Case Notes
`docs/testing/items/*.md` hold the durable step-by-step procedures and expectations for named test cases.

They may include:
- CLI commands
- GUI steps
- test data
- expected evidence
- cleanup steps

The dashboard may reference these cases, but the case notes remain the canonical procedure surface.

### 5. Relationship To Other Durable Surfaces
- CI remains the independent verifier for objective repository checks
- the forge remains the canonical issue, PR, review, and workflow-run history surface
- roadmap and WBS remain the planning and sequencing structure
- issue and decision dashboards remain the active current-state surfaces for blockers and major decisions
- testing docs complement these surfaces by making validation itself durable and repeatable

## Rationale

### Why Not Keep Testing Only In Issue Notes
Issue notes are good for active blockers, but they are too unstable to serve as the long-term home of reusable operator test procedures.

### Why Separate Plan, Framework, And Dashboard
- the plan defines scope and stable assumptions
- the framework defines how tests are executed and observed
- the dashboard tracks what still needs attention right now

This separation keeps the current-state view concise while preserving durable procedures elsewhere.

### Why Keep Canonical Cases Separate From The Dashboard
Canonical cases should remain stable even when the current-cycle dashboard items move out, split, or are refreshed for a new validation window.

### Why Use Move-Out Rules
Without move-out rules, a testing dashboard becomes a stale ledger instead of a useful near-term operator view.

## Consequences

### Positive
- local validation knowledge becomes reusable instead of chat-bound
- maintainers get a stable place to find exact CLI and GUI flows
- active test tracking can evolve without losing canonical test procedures
- future agent runs can write failures and follow-ups into a repeatable testing workflow

### Negative
- another document surface must be maintained
- humans and agents need discipline to keep the dashboard current and move out stale items
- some test work that previously lived only in transient notes now requires explicit write-back

## Follow-Up
This ADR should be supported by:
- a testing-management policy
- a testing dashboard and archive
- canonical test-case notes under `docs/testing/items/`
- a testing plan and testing framework
- roadmap, WBS, README, and agent-instruction updates so the workflow is discoverable
