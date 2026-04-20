# PR And CI Path Definition

## Purpose
This document defines the first proposal and independent verification path for the minimum closed loop.

It is the design deliverable for WBS `2.4` and follows ADR-0002.

## 1. Goals
- create a reviewable proposal in the forge as part of the first closed loop
- preserve CI as an independent verifier
- surface task and session traceability clearly enough for human review
- keep proposal creation separate from deploy or release actions

## 2. Non-Goals
- defining the full long-term release process
- replacing CI with agent-owned checks
- building a complete retry and recovery workflow in Phase 1

## 3. Phase 1 Decision
Phase 1 uses `create branch and PR immediately` as the first proposal path.

This means:
- the proposal surface appears in Gitea as early as the session can create it
- local checks may still run before or after PR creation, but the review surface is created immediately
- CI should attach to the PR path as the independent verification surface

## 4. Proposal Flow
The first intended flow is:

1. Accepted task starts an agent session.
2. Runtime prepares a working branch.
3. When the session has a minimally reviewable change set, it creates a branch and PR.
4. CI runs independently against the proposal path.
5. Human review decides merge or follow-up.

## 5. Traceability Display Strategy
Phase 1 uses:
- PR body summary for reviewer-facing traceability
- linked metadata artifact for machine-readable detail

The PR body should show at least:
- `task_request_id`
- `agent_session_id`
- source issue or PR reference when applicable
- selected execution profile

The linked metadata artifact may carry fuller machine-readable fields, including CI linkage.
When CI starts and finishes, the proposal path may refresh the reviewer-facing traceability block so the PR surface shows the current CI run and whether the proposal is ready for human review.

### 5.1 Concrete Proposal Conventions
The first proposal path should use these conventions:
- branch name: `agent/<task_request_id>`
- PR title: `agent: <summary-or-derived-task-label>`
- append source issue reference in the title when available, for example `agent: refresh architecture wording (#123)`
- PR body should include a dedicated `## Agent Traceability` block before the free-form rationale
- the linked metadata artifact should be committed in the proposal branch at `.agent-sdlc/traceability/<task_request_id>.json`

## 6. CI Trigger Rule
CI should run from the proposal path and remain independent of agent-owned local checks.

Local runtime checks may still run, but they do not replace CI as the decision-quality verifier.

The first CI trigger should run on:
- PR open
- PR update / synchronize
- PR reopen

The smallest sufficient Phase 1 CI policy is:
- every agent-opened PR must have at least one required CI workflow attached to the PR head
- that workflow must publish an objective pass/fail result in the PR surface
- the workflow should run the repository-local verification appropriate to the selected execution profile
- merge should remain blocked when the required CI result is missing, pending, or failing

## 7. Branch And PR Responsibilities

### Runtime / Proposal Logic
- prepare branch content
- create or update the proposal branch
- surface the PR with summary and traceability block

### CI
- run objective verification
- publish pass/fail results and supporting links

### Human Reviewer
- interpret the proposal and CI results
- accept, reject, or request follow-up

## 8. Failure Handling Guidance
If PR creation fails:
- the session should preserve artifacts and failure context
- the task should not silently proceed as if a proposal exists

If CI fails:
- the PR remains the review surface
- the result should be visible without requiring hidden runtime logs

## 9. Future Evolution Questions
- when should CI attach richer artifact links or structured annotations beyond the PR body traceability block?
