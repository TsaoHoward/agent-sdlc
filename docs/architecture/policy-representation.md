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

### 6.1 Exact Phase 1 File Schema Defaults
Phase 1 uses these concrete top-level keys:

#### `config/policy/task-classes.yaml`
- `version`
- `commandContract`
- `taskClasses`

Each `taskClass` entry should include:
- `id`
- `description`
- `commandTokens`
- `summaryRequired`
- `allowedSourceEventTypes`
- `defaultExecutionProfileId`
- `approvalRuleId`
- `policyRefs`

#### `config/policy/execution-profiles.yaml`
- `version`
- `executionProfiles`

Each `executionProfile` entry should include:
- `id`
- `description`
- `taskClassIds`
- `runtimeCapabilitySetId`
- `approvalRuleId`
- `policyRefs`

#### `config/policy/approval-rules.yaml`
- `version`
- `approvalRules`

Each `approvalRule` entry should include:
- `id`
- `description`
- `defaultApprovalState`
- `escalateOn`
- `rejectOn`
- `policyRefs`

#### `config/policy/runtime-capability-sets.yaml`
- `version`
- `runtimeCapabilitySets`

Each `runtimeCapabilitySet` entry should include:
- `id`
- `description`
- `filesystem`
- `network`
- `secrets`
- `git`
- `commandCategories`
- `policyRefs`

## 7. Repository Layout Guidance
The Phase 1 repository layout should reserve:
- `docs/policies/` for human-readable governance
- `config/policy/` for machine-readable policy

The machine-readable layer should be versioned in the same repository as the code and docs it governs.

Phase 1 chooses a split-by-policy-unit layout. A practical first layout is:
- `config/policy/task-classes.yaml`
- `config/policy/execution-profiles.yaml`
- `config/policy/approval-rules.yaml`
- `config/policy/runtime-capability-sets.yaml`

Source-specific mapping should be split as follows:
- config owns bounded mapping knobs such as allowed source event families, command tokens, summary requirements, and profile/capability selection
- adapter code owns raw webhook parsing, payload authentication, and source-specific field extraction
- docs own the rationale for why those mappings and approvals exist

### 7.1 Config Template Guidance
Configurable modules should follow ADR-0008 and `docs/policies/configuration-management.md`.

The default pattern is:
- checked-in templates define safe defaults and schema shape
- generated local config files carry operator-specific values and are ignored by Git when they may vary per environment
- loaders prefer local config, then template, then emergency code defaults

Machine-readable policy files under `config/policy/` are currently committed source-of-truth policy inputs, not generated local config. If a future policy unit needs operator-local overrides, it should add a template/local split explicitly rather than silently changing policy ownership.

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

### 9.1 Phase 1 Doc-Only Rules
The following rules remain doc-owned in Phase 1 and should not be duplicated as the primary source of truth in config:
- architecture boundary change approval requirements
- ADR promotion requirements
- human merge and release ownership
- cross-cutting rationale for why a task class is allowed or disallowed
