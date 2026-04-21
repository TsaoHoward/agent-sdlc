# Operating Model

## Purpose
This document defines how humans and agents collaborate in this repository.

## 1. Roles
### Human Owner / Maintainer
- approves direction
- approves architecture-level changes
- decides merge and release boundaries
- resolves ambiguous goals and scope conflicts

### Agent
- reads repository guidance
- proposes plans, updates documents, and implements bounded tasks
- does not silently redefine architecture or governance
- does not assume permanent authority over deployment or verification

### CI System
- validates builds, tests, lint, and other objective checks
- acts as an independent verifier

## 2. Work Sequence
1. A task is proposed or triggered.
2. Relevant documents are reviewed.
3. The task is mapped to roadmap/WBS.
4. If needed, an ADR is written or updated.
5. The agent works within the allowed boundary.
6. CI validates results.
7. A human reviews and decides next action.

## 3. Document Lifecycle
### Documents that should change often
- `docs/roadmap.md`
- `docs/wbs.md`
- `docs/user-capability-matrix.md`
- `docs/issues/issue-dashboard.md`
- `docs/issues/items/*.md` when active issues need supporting notes
- `docs/testing/test-dashboard.md`
- `docs/testing/items/*.md` when active test cases need supporting notes
- task-specific implementation notes if later added

### Documents that should change less often
- `docs/project-overview.md`
- `docs/architecture/*.md`
- `docs/policies/*.md`

### Documents that should change only on meaningful architecture decisions
- `docs/decisions/*.md`

## 4. When to Update What
### Update roadmap when:
- phase meaning changes
- milestone scope changes
- a new phase is introduced
- a durable user-facing workflow or capability surface is added, removed, or reframed
- a previously deferred capability is pulled forward

### Update WBS when:
- work items are created, split, merged, blocked, or completed
- dependencies change
- work ownership or deliverable meaning changes

### Update user capability matrix when:
- supported `@agent` locations change
- supported task tokens or parsing rules change
- the boundary between automated and manual operator workflow changes
- the current implemented lifecycle no longer matches what users are told the system can do

### Update issue dashboard when:
- meaningful active issues or blockers are created, split, merged, reframed, blocked, deferred, completed, or closed
- a dashboard item needs an explicit exit path
- a work item needs durable cross-run handoff context that does not belong only in chat

### Update test dashboard when:
- meaningful active validation items are created, reframed, blocked, failed, passed, deferred, or retired
- a dashboard item needs an explicit next action or exit path
- a local or GUI test procedure needs durable cross-run handoff context that does not belong only in chat

### Update canonical test notes when:
- a dashboard summary is no longer sufficient
- exact CLI or GUI steps changed
- default local data, credentials, repo names, or evidence paths changed
- an active test item needs deeper reusable procedure detail than the dashboard should hold

### Update supporting issue notes when:
- a dashboard summary is no longer sufficient
- background, evidence, dependencies, or recommended work packaging need durable capture
- an active issue needs more context than the dashboard should hold

### Update ADRs when:
- architecture boundaries shift
- replaceability assumptions shift
- governance or control-plane assumptions shift
- verification or deployment ownership changes

### Update decision backlog when:
- a meaningful unresolved major decision is discovered
- candidate directions for a major decision are narrowed
- a major direction is selected but not yet promoted to ADR
- a backlog item is promoted to ADR, deferred, or closed

When a backlog item is promoted to ADR or fully closed, move it out of the active dashboard so the backlog stays current-state oriented.
Keep detail decisions in supporting design or implementation notes unless they become major or blocking.

## 5. Human Approval Points
Human approval is required before:
- major scope expansion
- architecture boundary changes
- new durable policies
- changes in source-of-truth ownership
- deploy/release automation that affects production

## 6. Agent Guardrails
Agents should:
- prefer explicit assumptions over silent inference
- keep durable logic in repo documents where possible
- not treat recent chat context as the only authority
- not implement broad product features during planning phases
- use `docs/issues/issue-dashboard.md` as the durable dashboard for active near-term issue state
- use `docs/testing/test-dashboard.md` as the durable dashboard for active near-term validation state
- use `docs/decisions/decision-backlog.md` as the durable dashboard for near-term decision state

## 7. Early-Phase Bias
In early phases, prefer:
- architecture clarity
- interfaces over deep implementation
- scaffolding over heavy integration
- replaceable adapters over direct lock-in
