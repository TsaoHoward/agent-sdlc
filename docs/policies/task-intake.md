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

## 7. Routing Guidance
Task intake should decide:
- whether the task is executable
- which policy profile applies
- which runtime capability set applies
- whether a human approval checkpoint is required before execution

## 8. Traceability Rule
Each task should be traceable from:
- raw event
- normalized task request
- execution session
- resulting proposal
- CI result
