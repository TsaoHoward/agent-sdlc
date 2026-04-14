# Decision Backlog

## Purpose
This document captures the near-term decisions that still need explicit direction before or during Phase 1 implementation.

It is not an ADR. It is a staging document for decisions that may later become ADRs, policy updates, or implementation notes.

## How To Use This Document
- use it to understand why a decision matters before writing code
- use it to compare candidate directions at the right layer
- promote an item to an ADR when it changes architecture, source-of-truth ownership, runtime isolation assumptions, or verification/deploy ownership

## Current State
The project has already decided:
- first forge target: `Gitea`
- first policy representation model: `docs/policies/*.md` plus `config/policy/`
- first runtime isolation model: ephemeral container per task/session

The remaining items below are the next decisions needed to move from design baseline to implementable Phase 1 work.

## 1. First Gitea Trigger Path
Status: Decided on 2026-04-14
Chosen Direction: Option A - Issue Comment Command

### Background
The task intake contract already recommends `Gitea issue comment command` as the first executable path because it is explicit and auditable.

This decision is still open because the exact first trigger path determines:
- which webhook or event family the adapter implements first
- what command syntax humans use
- how much ambiguity the task gateway has to resolve

### Why It Matters
This is the entry point for WBS `3.1 Trigger Adapter Implementation`.

If this is left vague, the first adapter may mix multiple event types and hide policy decisions inside adapter code.

### Candidate Directions
#### Option A - Issue Comment Command
- explicit user intent
- lower ambiguity
- easier review trail

#### Option B - Issue Label Trigger
- simpler UI for users
- higher ambiguity
- more accidental execution risk

#### Option C - PR Comment Command
- useful for review follow-up tasks
- narrower initial use case
- less suitable as the only first path

### Recommended Direction
Choose `Issue Comment Command` as the first supported path.

### Decision To Make
- exact command form
- whether only repository members can trigger it
- whether commands may carry free-form instructions or only task-class selectors

## 2. Minimum Machine-Readable Policy Schema
Status: Decided on 2026-04-14
Chosen Direction: Option B - Split Files By Policy Unit

### Background
ADR-0002 decided that durable governance lives in docs and executable policy lives in `config/policy/`.

What remains open is the minimum schema needed for automation.

### Why It Matters
This blocks:
- task classification
- execution-profile selection
- runtime capability resolution
- approval and escalation logic

### Candidate Directions
#### Option A - Single File Policy
- one YAML file for all task classes, profiles, and rules
- easy to start
- likely to become crowded quickly

#### Option B - Split Files By Policy Unit
- separate files for task classes, execution profiles, approval rules, and capability sets
- clearer ownership and easier review
- slightly more plumbing in the loader

#### Option C - Hard-Code First, Externalize Later
- fastest prototype path
- directly conflicts with the architecture intent
- highest drift risk

### Recommended Direction
Choose `Split Files By Policy Unit`.

### Decision To Make
- exact file layout under `config/policy/`
- whether policy identifiers are strings or namespaced strings
- how docs and config reference each other

## 3. Agent Control Integration Plan
Status: Decided on 2026-04-14
Chosen Direction: Option A - Direct Session Starter Interface

### Background
WBS `2.2` is still open.

The architecture already says the Agent Control Plane starts sessions, assembles context, and hands off to runtime. What remains open is the first concrete interface shape.

### Why It Matters
This decision determines:
- what the task gateway sends downstream
- how sessions are tracked
- where execution metadata is recorded

### Candidate Directions
#### Option A - Direct Session Starter Interface
- task gateway calls a session-starter component with a normalized task request
- simple first closed loop
- good fit for single-runner Phase 1

#### Option B - Queue-Based Control Plane
- task gateway enqueues tasks and a separate control component consumes them
- better separation and resilience
- heavier for the first loop

#### Option C - Embed Agent Launch Inside Task Gateway
- fewer components
- weaker boundary between intake and control
- higher architectural drift risk

### Recommended Direction
Choose `Direct Session Starter Interface` for Phase 1, but keep the interface abstract enough to move behind a queue later.

### Decision To Make
- session start API or command contract
- minimum session state model
- where session metadata is persisted

## 4. PR And CI Path Definition
Status: Decided on 2026-04-14
Chosen Direction: Option A - Create Branch And PR Immediately

### Background
WBS `2.4` is still open.

The system already requires independent CI and a human review gate, but the first proposal path still needs a concrete definition.

### Why It Matters
This decision determines:
- when a branch is created
- when a PR is created
- how CI is attached to the proposal
- where traceability fields are surfaced for reviewers

### Candidate Directions
#### Option A - Create Branch And PR Immediately
- clearest review surface
- fastest route to the intended user experience
- may create noisy PRs if the task fails late

#### Option B - Create Branch First, PR Only After Local Checks
- reduces low-quality PR churn
- slightly more lifecycle complexity

#### Option C - Produce Artifact First, Human Promotes To PR
- strongest manual gate
- weaker end-to-end automation value for Phase 1

### Recommended Direction
Choose `Create Branch First, PR After Local Checks` if the local checks are lightweight; otherwise use `Create Branch And PR Immediately` with draft PR semantics if available.

Selected for Phase 1:
- create branch and PR immediately
- use the PR as the earliest review surface

### Decision To Make
- exact PR creation timing
- where CI is triggered from
- where `task_request_id` and `agent_session_id` appear

## 5. Runtime Network And Secret Defaults
Status: Decided on 2026-04-14
Chosen Direction: Option C - Broad Egress For Simplicity

### Background
Runtime isolation is now defined at the strategy level, but the default capability profile is still open.

### Why It Matters
This is the most security-sensitive near-term decision.

It determines:
- what the first runtime can reach
- what credentials it receives
- what package installs or remote fetches are possible

### Candidate Directions
#### Option A - Deny By Default, Forge Only
- safest
- may block common build flows

#### Option B - Allow Forge Plus Required Package Registries
- practical balance for Phase 1
- requires explicit allowlist work

#### Option C - Broad Egress For Simplicity
- easiest to prototype
- weakens the runtime boundary too early

### Recommended Direction
Choose `Forge Plus Required Package Registries`, with profile-specific secret injection.

Selected for Phase 1:
- broad egress by default
- minimal, profile-specific secret injection

Because this weakens the earlier preferred posture, it should be recorded as an ADR-backed temporary implementation compromise.

### Decision To Make
- exact allowlist
- which profiles can receive secrets
- whether secrets are environment variables, mounted files, or brokered tokens

## 6. Traceability Display Strategy
Status: Decided on 2026-04-14
Chosen Direction: Option A - PR Body Summary Plus Linked Metadata Artifact

### Background
The lifecycle traceability contract defines the required identifiers, but not the exact first reviewer-facing display pattern.

### Why It Matters
If traceability exists only in backend artifacts, the review surface becomes weak. If it is too verbose, the proposal surface becomes noisy.

### Candidate Directions
#### Option A - PR Body Summary Plus Linked Metadata Artifact
- reviewer-friendly
- keeps machine-readable detail out of the main prose

#### Option B - Structured Comment Only
- easier to append after PR creation
- easier to miss during review

#### Option C - Artifact Only
- clean UI
- weak human visibility

### Recommended Direction
Choose `PR Body Summary Plus Linked Metadata Artifact`.

### Decision To Make
- exact metadata fields shown in PR body
- whether CI run links are added to the same block
- whether review decision references must be visible at merge time

## Promotion Guidance
Promote a backlog item into an ADR when:
- it changes architecture boundaries
- it changes source-of-truth ownership
- it changes runtime isolation assumptions
- it changes CI or deploy ownership

Otherwise, the item may be resolved in:
- a policy update
- a design spec
- a bounded implementation note
