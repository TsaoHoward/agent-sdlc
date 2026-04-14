# Task Intake Contract

## Purpose
This document defines the Phase 1 contract between source events and the normalized task request used by downstream layers.

It is the design deliverable for WBS `2.1` and follows ADR-0002.

## 1. Goals
- keep source-specific event details out of downstream layers
- give task gateway a stable normalized contract
- carry policy and approval context into agent control and runtime
- support Gitea as the first forge target without binding the architecture to Gitea-only semantics

## 2. Non-Goals
- defining every future source adapter
- defining the full PR and CI proposal flow
- defining the internal prompt or tool payload used by a specific agent product

## 3. First Target Assumption
Phase 1 assumes:
- first forge target: `Gitea`
- first execution-policy source: `config/policy/`
- first runtime strategy: ephemeral container-based worker per task/session

## 4. Contract Ownership

### Source Event Shape Is Owned By
- Gitea or another upstream source system

### Normalized Task Request Is Owned By
- Trigger / Task Gateway / Orchestration Adapter layer

### Policy Resolution Inputs Are Owned By
- Context / Policy layer

Downstream layers should consume the normalized contract, not raw Gitea payloads.

## 5. Normalized Task Request
The task gateway should emit one normalized task request per accepted executable task.

### 5.1 Required Fields
| Field | Type | Meaning |
|---|---|---|
| `task_request_id` | string | stable identifier for the normalized task request |
| `source_system` | string | source family, for Phase 1 this is `gitea` |
| `source_event_id` | string | stable upstream event reference when available |
| `source_event_type` | string | normalized event type label from the source adapter |
| `repository_ref` | string | stable repository identifier |
| `default_branch_ref` | string | repository default branch at intake time |
| `target_branch_ref` | string | branch context the task should evaluate against |
| `trigger_actor_ref` | string | actor who triggered the request when available |
| `task_class` | string | normalized task classification |
| `execution_profile_id` | string | selected execution profile |
| `runtime_capability_set_id` | string | resolved runtime capability set |
| `approval_state` | string | `auto-approved`, `approval-required`, or `rejected` |
| `policy_refs` | string[] | policy or ADR references used for the decision |
| `traceability_refs` | object | seed references needed by downstream layers |
| `submitted_at` | string | intake timestamp in UTC ISO-8601 form |

### 5.2 Conditional Fields
| Field | Type | Meaning |
|---|---|---|
| `issue_ref` | string | issue identifier when the event came from issue scope |
| `pull_request_ref` | string | PR identifier when the event came from PR scope |
| `comment_ref` | string | comment identifier when a comment triggered the task |
| `label_ref` | string | label identifier when a label event triggered the task |
| `command_text` | string | parsed command or normalized intent when applicable |
| `approval_reason` | string | required when `approval_state` is not `auto-approved` |
| `rejection_reason` | string | required when `approval_state` is `rejected` |
| `source_payload_ref` | string | pointer to stored raw payload or raw-event evidence when retained |

## 6. Task Classes
Phase 1 supports at least these normalized task classes:
- `documentation_update`
- `bounded_code_change`
- `review_follow_up`
- `ci_failure_investigation`
- `unsafe_or_high_risk`

The task gateway may map multiple Gitea event shapes into the same task class.

## 7. Approval States
The normalized task request must carry one of these approval states:
- `auto-approved`
- `approval-required`
- `rejected`

The task gateway decides this state after policy resolution and before agent control starts a session.

## 8. First-Phase Gitea Event Mapping
The adapter may support multiple Gitea events over time, but the normalized contract should use these source event families:
- `issue_comment`
- `issue_label`
- `pull_request_comment`
- `manual_submission`

### First Trigger Path
For Phase 1, the first executable trigger path is:
- `Gitea issue comment command -> normalized task request`

Why this path was chosen:
- explicit human intent
- lower ambiguity than passive label-driven execution
- easier auditability for the first closed loop

## 9. Policy Resolution Requirements
Before the task request is accepted for execution, the task gateway must resolve:
- `task_class`
- `execution_profile_id`
- `runtime_capability_set_id`
- `approval_state`
- `policy_refs`

Raw source events must not be passed downstream as a substitute for these decisions.

## 10. Rejection Conditions
The task gateway must reject or escalate when:
- the source event cannot be mapped to a supported task class
- required repository or branch context is missing
- the request exceeds the selected execution profile
- the request implies architecture, policy, security-sensitive, or deploy authority without approval
- policy lookup fails in a way that prevents a safe decision

## 11. Traceability Requirements
The normalized task request must seed downstream traceability by carrying:
- `task_request_id`
- `source_event_id`
- `repository_ref`
- issue, PR, comment, or label refs when applicable
- policy and ADR references used at intake time

These references become the stable handoff point for agent control, proposal generation, CI, and human review.

## 12. First-Phase Persistence Guidance
Phase 1 should preserve the normalized task request in a machine-readable record that can be referenced by downstream layers.

A practical first-phase approach is:
- store the normalized request as a session artifact or structured metadata record
- carry `task_request_id` into proposal, CI, and review surfaces

## 13. Open Questions
- what exact issue-comment command syntax should Gitea use first?
- should `repository_ref` be forge-local only or include a globally unique namespaced form?
- when source events lack a stable event ID, which adapter-generated fallback ID format should be used?
