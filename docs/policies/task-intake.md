# Task Intake Policy

## Purpose
This document defines the baseline rules for accepting, classifying, and routing tasks into agent execution.

## 1. Intake Principles
- Every executable task should come from a normalized task request.
- Unsupported or high-risk tasks should be rejected or escalated before execution.
- Intake rules should remain separate from downstream implementation details.

## 2. Candidate Task Sources
Possible sources include:
- issue labels
- issue comments
- PR comments
- explicit task submissions from later adapters

For the first Gitea trigger path, the preferred source is:
- issue comment command using a bounded mention-style command format

## 3. Minimum Required Task Metadata
A normalized task request should include at least:
- source system
- repository identifier
- relevant issue or PR identifier when applicable
- triggering user or actor identifier when available
- task class
- allowed execution profile or capability set
- relevant branch context
- links to applicable policy/context references

If the task was triggered by a bounded comment command, intake should also preserve:
- the recognized command form
- the parsed task class token
- the bounded summary text when present

## 4. Early-Phase Task Classes
Suggested early task classes:
- documentation update
- bounded code change
- review follow-up
- CI failure investigation
- unsafe/high-risk request (reject or escalate)

## 5. Rejection Conditions
Reject or escalate when:
- the event cannot be mapped to a supported task class
- the task lacks required identifiers or repository context
- the requested action exceeds allowed capability boundaries
- the task would bypass required human approval
- the request implies direct production deployment authority without explicit approval model
- the issue comment command exceeds the allowed bounded free-form format

## 6. Approval Guidance
### Can proceed automatically in early phases
- low-risk documentation tasks
- bounded implementation tasks inside approved scope
- follow-up changes on already open proposals if policy allows

### Should require explicit approval or escalation
- architecture changes
- policy changes
- deployment/release changes
- security-sensitive or secret-handling changes
- actions that expand the system boundary

## 7. Early-Phase Execution Profiles
### Profile A - Documentation Safe
- intended for documentation, planning, prompt, and repository-guidance updates
- may edit durable text artifacts and run low-risk repository-local checks
- should not modify deploy/release paths, secret-handling behavior, or system boundaries

### Profile B - Bounded Change
- intended for small code, config, or documentation changes inside approved roadmap/WBS scope
- may use the allowed repository-local verification commands for the task
- should not change architecture boundaries, policy ownership, CI ownership, or deploy authority without escalation

### Profile C - Investigation Only
- intended for reproduction, inspection, CI-failure investigation, and evidence gathering
- may collect logs, produce analysis, and propose next steps
- should avoid durable code changes unless a follow-up task explicitly allows them

### Profile D - Escalation Required
- used when the task touches architecture, policy, security-sensitive behavior, secrets, deployment/release, or boundary expansion
- should stop before execution beyond assessment until explicit human approval exists

## 8. Routing Guidance
Task intake should decide:
- whether the task is executable
- which policy profile applies
- which runtime capability set applies
- whether a human approval checkpoint is required before execution

The routing decision should produce or reference at least:
- normalized task class
- selected execution profile
- approval state or escalation requirement
- applicable policy and ADR references
- runtime capability set
- traceability identifiers needed by downstream layers

## 9. Minimum Traceability Fields
The durable task record should preserve at least these linkable fields:
- `source_event_id` or equivalent source event reference
- `task_request_id`
- `execution_profile_id` or equivalent policy profile reference
- `agent_session_id` when a session starts
- `proposal_ref` when a reviewable change is created
- `ci_run_ref` when independent verification runs
- `review_decision_ref` when a human approval or rejection is recorded

## 10. Traceability Rule
Each task should be traceable from:
- raw event
- normalized task request
- execution session
- resulting proposal
- CI result

These references should survive handoff across logs, proposal text, or machine-readable metadata so downstream review does not depend on chat history alone.
