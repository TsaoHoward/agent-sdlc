# ADR-0002: Phase 1 Target Choices for Forge, Policy Representation, and Runtime Isolation

- Status: Accepted (Phase 1 planning baseline)
- Date: 2026-04-14

## Context
ADR-0001 established the layer boundaries for the agent-oriented SDLC platform, but it intentionally deferred the first implementation target choices.

Phase 1 now needs enough specificity to:
- define the first task intake contract
- define the first lifecycle traceability contract
- avoid pushing durable policy into prompts or ad hoc code
- avoid collapsing runtime isolation into an unspecified local process model

The project still needs to preserve replaceability at the architecture seams defined in ADR-0001.

## Decision
For Phase 1 planning and initial implementation:

1. The first forge / PM target is `Gitea`.
2. The first policy representation model is a dual-layer repository model:
   - human-governed policy and rationale in `docs/policies/*.md`
   - machine-readable execution policy in repository configuration under `config/policy/`
3. The first runtime isolation strategy is an ephemeral container-based worker per task/session.

## Decision Details

### 1. First Forge Target: Gitea
Gitea is the first supported forge target for the minimum closed loop.

This means the first task intake and proposal flow should assume:
- Gitea-originated issue, PR, label, or comment events
- Gitea repository and proposal identifiers
- Gitea as the first review and merge surface

This does not change the architecture requirement that downstream contracts remain source-normalized and replaceable.

### 2. First Policy Representation: Docs Plus Repo Config
The first policy model is split across:

#### Durable Governance Layer
- `docs/policies/*.md`
- ADRs in `docs/decisions/*.md`

This layer explains:
- policy intent
- approval rules
- change control
- architecture and governance rationale

#### Machine-Readable Execution Layer
- repository configuration under `config/policy/`

This layer is intended to carry:
- task-class mappings
- execution profile definitions
- approval and escalation rules needed by automation
- capability constraints needed by the task gateway or runtime

The docs remain the primary human review surface. The config provides executable policy without moving durable governance into code or prompts.

### 3. First Runtime Isolation Strategy: Ephemeral Container Per Session
The first runtime strategy is:
- one isolated container per task/session
- fresh repository checkout or equivalent session-local workspace inside the container
- non-root execution
- no host Docker socket or equivalent host-control escape hatch
- explicit artifact export for logs, patch data, and verification outputs
- explicit and minimal secret injection only when required
- restricted network posture, opened only as needed for the supported workflow

This decision establishes the default isolation boundary for the first closed loop without committing the project to Docker-specific architecture long term.

## Rationale

### Why Gitea First
- narrows the first integration surface
- enables concrete intake and proposal specs
- does not prevent future forge adapters

### Why Docs Plus Config for Policy
- keeps governance reviewable in repository docs
- gives automation a stable machine-readable layer
- avoids turning prompt text into the effective policy engine

### Why Container-Based Runtime Isolation
- preserves a clear runtime boundary
- reduces coupling to the host environment
- aligns with the architecture requirement that runtime be isolated by default

## Consequences

### Positive
- Phase 1 design work can proceed against a specific forge surface
- policy can be enforced without hiding it in runtime code
- runtime boundaries become concrete enough for capability modeling

### Negative
- repository structure grows earlier than a pure prototype might require
- the first specs will carry Gitea-specific mapping details
- some implementation details remain open beneath the chosen isolation model

## Follow-Up
This ADR should be followed by:
- a policy representation architecture note
- a runtime isolation architecture note
- a Gitea-oriented task intake contract spec
- a lifecycle traceability contract spec

Open implementation questions remain, including:
- the first supported Gitea trigger path
- the exact machine-readable policy schema
- the exact container runner technology and network allowlist
