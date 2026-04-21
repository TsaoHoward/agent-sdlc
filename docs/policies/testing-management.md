# Testing Management Policy

## Purpose
This document defines how stable test procedures, active test tracking, and test-case write-back should be managed in repository documents.

It supports ADR-0007 and standardizes a durable collaboration workflow for humans and AI agents.

## 1. Core Rule
Meaningful testing knowledge should live in repository documents, not only in chat, shell history, or one-off PR comments.

Chat may summarize a test run or suggest next steps, but the repository is the durable testing workflow surface.

## 2. Primary Testing Surfaces

### 2.1 Test Plan
`docs/testing/test-plan.md` is the stable testing-scope document.

Use it for:
- local test objectives
- environment matrix
- stable default test data
- entry and exit criteria
- suite-level coverage planning

### 2.2 Test Framework
`docs/testing/test-framework.md` defines how testing is executed and observed.

Use it for:
- execution modes
- evidence expectations
- naming and status conventions
- failure write-back rules

### 2.3 Test Dashboard
`docs/testing/test-dashboard.md` is the active dashboard for near-term test work that still deserves operator attention.

Use it for:
- active regression-watch items
- current blocked or failed validation cases
- near-term manual validation gaps
- next actions that should survive across runs

It should not become:
- a permanent historical ledger
- a replacement for CI run history
- a replacement for issue or decision dashboards

### 2.3.1 Move-Out Rule
When a dashboard item reaches one of these states:
- `Passed`
- `Retired`

it should move out of the active dashboard at the next maintenance pass when it no longer needs operator attention.

When a dashboard item is `Deferred`, it should also move out when it is no longer near-term.

Move it to:
- `docs/testing/test-archive.md` when a lightweight history entry is still useful
- the canonical case note under `docs/testing/items/` when the current-cycle dashboard no longer needs to carry it directly

### 2.3.2 Active Dashboard Rule
The dashboard table in `docs/testing/test-dashboard.md` should show only active or near-term testing work that still deserves operator attention.

### 2.4 Canonical Test Case Notes
Use `docs/testing/items/` for canonical test-case definitions and detailed procedures.

Canonical case notes are the place for:
- CLI commands
- GUI steps
- expected evidence
- cleanup steps
- stable test data

Case notes should remain stable even when dashboard items move out.

### 2.5 Test Archive
`docs/testing/test-archive.md` is the move-out surface for test items that no longer need active dashboard visibility.

## 3. Required Dashboard Item Fields
Each active test-dashboard item should include at least:
- test title
- current status
- execution mode
- related docs or WBS references
- why the test matters
- current state summary
- next action
- exit path
- canonical case-note reference when one exists
- escalation guidance when failures should update issue, decision, roadmap, WBS, or ADR docs

## 4. Standard Status Model
Use one of these statuses:
- `Draft`
- `Ready`
- `In Progress`
- `Blocked`
- `Passed`
- `Failed`
- `Deferred`
- `Retired`

`Passed` and `Retired` are transition-end states and should usually trigger move-out from the active dashboard once the current validation window no longer needs them.

## 5. Agent Workflow Requirements
Before substantial work on an active test item, an AI agent should read any referenced canonical case note under `docs/testing/items/`.

When an AI agent encounters a meaningful testing change, the agent should:
1. update `docs/testing/test-plan.md` when stable scope, default data, or entry/exit criteria changed
2. update `docs/testing/test-framework.md` when execution modes, evidence rules, or write-back expectations changed
3. add or update the item in `docs/testing/test-dashboard.md` when active near-term validation state materially changed
4. create or update a canonical case note when the dashboard summary is no longer sufficient
5. update issue, decision, roadmap, WBS, policy, or ADR docs in the same maintenance pass when test results materially affect those surfaces

When an AI agent resolves or reframes a test item, the agent should:
1. update the dashboard item status
2. move the item out of the active dashboard when it no longer deserves operator attention
3. update `docs/testing/test-archive.md` when a lightweight history record is still useful
4. leave an explicit note when related follow-up remains intentionally open

Do not leave meaningful testing state only in chat if it affects future work.

## 6. Human Workflow Guidance
Humans may use the testing docs to:
- find exact local CLI and GUI validation steps
- understand which local data, accounts, and URLs are expected
- see which manual validations are still active
- understand how a test result should be written back into issues, decisions, or planning docs

## 7. Escalation Rules
Escalate a testing result into issue tracking when it reveals:
- an active blocker
- a regression
- a new execution gap

Escalate a testing result into the decision backlog when it reveals a major unresolved decision about workflow, ownership, security, or validation strategy.

Escalate a testing result into an ADR when it changes:
- architecture boundaries
- source-of-truth ownership
- verification ownership
- deployment responsibility
- cross-cutting governance expectations

## 8. Anti-Patterns
Do not:
- keep important test steps only in chat
- treat the dashboard as the only home of canonical procedures
- replace CI history with repo-local prose
- keep passed, retired, or stale items in the active dashboard indefinitely
- let case notes drift away from the plan, framework, issues, or WBS they support
