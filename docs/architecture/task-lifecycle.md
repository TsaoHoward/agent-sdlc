# Task Lifecycle

## Purpose
This document describes the intended lifecycle of work from external event to verified change proposal.

## Target Lifecycle
1. External event occurs.
2. Task intake receives the event.
3. Event is normalized into a task request.
4. Intake policy determines whether and how the task can proceed.
5. Agent control starts a bounded session.
6. Execution runtime prepares the workspace.
7. Agent performs analysis and bounded changes.
8. Proposed changes are surfaced as branch/PR or equivalent.
9. CI validates the proposal independently.
10. Human reviews and decides next action.
11. Approved changes move to normal release/deploy flow.

## Detailed Steps

### 1. External Event
Possible triggers:
- issue label added
- issue comment command
- PR comment command
- explicit task submission through another adapter

Output:
- raw event payload

### 2. Task Intake
Responsibilities:
- authenticate or trust event source
- extract key identifiers
- reject unsupported or unsafe task classes early

Output:
- accepted or rejected intake decision

### 3. Task Normalization
Responsibilities:
- convert raw event into a stable task request contract
- include repo, branch, issue/PR context, task class, constraints, and policy references

Output:
- normalized task request

### 4. Policy Check
Responsibilities:
- determine whether the task can run automatically
- determine allowed capabilities
- determine required approvals or restricted commands

Output:
- task execution profile

### 5. Agent Session Start
Responsibilities:
- load context
- attach tools/skills
- record execution metadata
- hand off to runtime boundary

Output:
- active agent session

### 6. Runtime Preparation
Responsibilities:
- prepare isolated workspace
- mount or checkout repository
- apply bounded execution context
- prepare logs/artifacts location

Output:
- execution-ready workspace

### 7. Agent Work
Responsibilities:
- inspect context
- propose and apply bounded edits
- run allowed checks
- prepare summary and change set

Output:
- proposed code/config/doc change set

### 8. Proposal Surface
Responsibilities:
- create branch/PR or equivalent proposal
- attach summary, rationale, and traceability info

Output:
- reviewable proposal in forge

### 9. Independent Verification
Responsibilities:
- run CI checks
- publish objective results

Output:
- pass/fail and supporting logs

### 10. Human Review
Responsibilities:
- assess correctness, scope, and risk
- request changes, accept, or reject

Output:
- merge decision or follow-up task

### 11. Release Handoff
Responsibilities:
- continue through normal release/deploy controls
- maintain separation from coding-agent execution

Output:
- approved changes enter release flow

## Lifecycle Rules
- Normalization must happen before agent execution.
- Policy must be applied before runtime execution.
- CI must remain independent.
- Deploy is downstream and separate.
- Traceability should be preserved from event -> task -> proposal -> validation.

## Minimum Closed Loop Definition
A minimum closed loop exists when:
- one supported external event can become a normalized task
- the task can start a bounded agent session
- the agent can produce a reviewable proposal
- CI can validate it independently
- a human can review it as a normal change
