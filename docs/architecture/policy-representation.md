# Policy Representation

## Purpose
This document defines how durable policy should be represented for the first implementation phases.

It refines the Context / Policy layer in `docs/architecture/overview.md` and follows ADR-0002.

## 1. Goals
- keep durable policy reviewable in the repository
- provide machine-readable policy inputs for task gateway and runtime enforcement
- avoid storing durable policy only in prompts or implementation code
- preserve replaceability between policy authorship, policy storage, and enforcement logic

## 2. Non-Goals
- building a full external policy service in Phase 1
- defining a final long-term policy language
- moving governance ownership away from repository docs

## 3. Representation Model
Phase 1 uses a dual-layer representation model.

### 3.1 Governance Layer
Human-governed policy lives in:
- `docs/policies/*.md`
- `docs/decisions/*.md`

This layer defines:
- allowed and disallowed task classes
- approval and escalation expectations
- architecture and governance rationale
- policy ownership and change-control requirements

### 3.2 Execution Layer
Machine-readable policy lives in:
- `config/policy/`

This layer is intended to define:
- task classes
- execution profiles
- approval requirements needed by automation
- runtime capability sets
- source-specific mapping knobs where needed

## 4. Ownership Model

### Docs Own
- policy intent
- governance rules
- approval model
- architecture-level rationale

### Machine-Readable Config Owns
- executable mappings and selectors
- profile IDs and capability IDs
- thresholds or flags needed by automation

### Code Should Not Own
- the primary definition of durable policy
- architecture-level approval rules
- source-of-truth decisions about governance

## 5. Policy Resolution Flow
The intended resolution flow is:

1. A source event arrives at the task gateway.
2. The task gateway normalizes the event into a task request.
3. The task gateway resolves applicable policy from `config/policy/`.
4. The resolved policy points back to durable policy docs and ADRs where needed.
5. The task request carries policy references and execution profile IDs downstream.

## 6. Minimum Phase 1 Policy Units
Phase 1 should support at least these machine-readable units:
- `taskClass`
- `executionProfile`
- `approvalRule`
- `runtimeCapabilitySet`

The exact schema may evolve, but these concepts should remain explicit.

## 7. Repository Layout Guidance
The Phase 1 repository layout should reserve:
- `docs/policies/` for human-readable governance
- `config/policy/` for machine-readable policy

The machine-readable layer should be versioned in the same repository as the code and docs it governs.

## 8. Enforcement Points

### Task Gateway
- task classification
- execution-profile selection
- approval or escalation decision

### Runtime
- command, filesystem, network, and secret constraints derived from the selected profile

### CI
- independent verification only

CI may validate results, but it should not become the primary policy authoring surface.

## 9. Change Control
Changes to policy representation should be handled as follows:
- schema additions or non-boundary config refinements are usually planning or implementation work
- changes to policy ownership or source-of-truth model require ADR review

## 10. Open Questions
- what is the minimum viable schema for `config/policy/`?
- which rules should remain doc-only in Phase 1?
- how much source-specific mapping belongs in config versus adapter code?
