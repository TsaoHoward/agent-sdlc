# Lifecycle Traceability Contract

## Purpose
This document defines the minimum traceability contract that connects intake, execution, proposal, verification, and review.

It is the design deliverable for WBS `2.5` and follows ADR-0002.

## 1. Goals
- preserve end-to-end traceability across layer handoffs
- make identifiers stable enough for automation, audit, and review
- avoid relying on chat history or transient runtime memory as the only record
- keep traceability separate from vendor-specific implementation details where practical

## 2. Non-Goals
- defining a full observability platform
- defining a permanent audit data warehouse
- requiring a single storage backend for every artifact

## 3. Core Traceability Principle
Every accepted executable task should be traceable across this chain:

`source event -> normalized task request -> agent session -> change proposal -> CI run -> human review decision`

## 4. Traceability Records

### 4.1 Source Event Record
Owned by:
- source system
- task gateway when raw-event evidence is retained

Required references:
- `source_system`
- `source_event_id`
- `source_event_type`
- repository and actor references when available

### 4.2 Task Request Record
Owned by:
- task gateway

Required references:
- `task_request_id`
- `source_event_id`
- `execution_profile_id`
- `policy_refs`
- issue, PR, comment, or label refs when applicable

### 4.3 Agent Session Record
Owned by:
- agent control plane

Required references:
- `agent_session_id`
- `task_request_id`
- `runtime_capability_set_id`
- session status
- start and end timestamps

### 4.4 Proposal Record
Owned by:
- forge / proposal surface
- proposal creation logic

Required references:
- `proposal_ref`
- `task_request_id`
- `agent_session_id`
- branch reference

### 4.5 Verification Record
Owned by:
- CI layer

Required references:
- `ci_run_ref`
- `proposal_ref`
- `task_request_id`
- verification status

### 4.6 Human Review Record
Owned by:
- forge review surface or equivalent approval system

Required references:
- `review_decision_ref`
- `proposal_ref`
- `task_request_id`
- decision outcome
- reviewer reference when available

## 5. Identifier Generation Rules

### Upstream-Owned Identifiers
These should come from the source system when available:
- `source_event_id`
- issue, PR, comment, and label refs
- `proposal_ref`
- `review_decision_ref`

### Platform-Owned Identifiers
These should be created inside the platform:
- `task_request_id`
- `agent_session_id`
- adapter-generated fallback event ID when upstream lacks one

### External Verifier Identifiers
These should come from the verification system:
- `ci_run_ref`

## 6. Required Cross-Layer Linkages
The following linkages are mandatory in Phase 1:
- task request must link to source event
- agent session must link to task request
- proposal must link to task request and agent session
- CI run must link to proposal and task request
- review decision must link to proposal and task request

## 7. First-Phase Persistence Surfaces
Phase 1 does not require a single centralized traceability database.

The minimum viable persistence model is:
- source and proposal identifiers in Gitea
- normalized task request record at `.agent-sdlc/state/task-requests/<task_request_id>.json`
- agent session metadata record at `.agent-sdlc/state/agent-sessions/<agent_session_id>.json`
- CI artifact or CI metadata carrying `task_request_id` and `proposal_ref`
- review decision reference preserved in the forge review surface

Task-request and session records should be retained for at least:
- the lifetime of the open proposal, when a PR exists
- 30 days after the final PR close or merge state
- 30 days after session completion when no PR is created

## 8. First-Phase Display Surfaces
Phase 1 uses:
- PR body summary for reviewer-facing traceability
- linked metadata artifact for machine-readable detail

The first closed loop should make it practical for a reviewer to recover:
- what source event started the work
- which task request was accepted
- which agent session produced the proposal
- which CI run verified it

The PR body should show at least:
- `task_request_id`
- `agent_session_id`
- source issue or PR reference when applicable

The linked metadata artifact may carry fuller machine-readable linkage.

The recommended PR block format is:

```markdown
## Agent Traceability
- Task Request: `<task_request_id>`
- Agent Session: `<agent_session_id>`
- Source: `<issue-or-pr-ref>`
- Execution Profile: `<execution_profile_id>`
- Runtime Capability Set: `<runtime_capability_set_id>`
- Metadata: `.agent-sdlc/traceability/<task_request_id>.json`
- Verification Metadata: `.agent-sdlc/ci/verification-metadata.json`
- CI: `pending` or `<ci_run_ref/link>`
- Review Status: `awaiting CI and human review` or `ready for human review`
```

`agent_session_id` should remain visible in the reviewer-facing block so a reviewer can correlate the PR with the session record without opening backend-only storage.
Phase 1 may refresh this block from CI so reviewers can see the current CI run and whether the proposal is blocked on failing verification without opening backend-only storage.

## 9. Failure Handling Rule
If a downstream record cannot link back to its required upstream reference, the system should treat that state as degraded traceability and either:
- fail closed for automated continuation, or
- explicitly mark the run as incomplete and require human follow-up

Silent unlinking is not acceptable.

## 10. Future Evolution Questions
- when should the project promote traceability storage from file-backed records to a dedicated service or audit store?
