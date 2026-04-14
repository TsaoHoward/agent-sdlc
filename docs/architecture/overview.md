# Architecture Overview

## Purpose
This document defines the primary architectural boundaries for the project.

The target user experience may feel unified, but the internal system must remain layered.

## 1. Layer Model
The system should separate at least the following layers:

1. Forge / PM layer
2. Trigger / Task Gateway / Orchestration Adapter layer
3. Context / Policy layer
4. Agent Control Plane layer
5. Execution Runtime layer
6. Verification / CI layer
7. Deploy / Release layer

## 2. Layer Responsibilities

### 2.1 Forge / PM Layer
**Responsibilities**
- repositories
- issues
- pull requests / merge requests
- comments, labels, review state
- workflow definition files
- collaboration surface for humans

**Should not own**
- durable orchestration logic
- agent planning logic
- CI verification semantics beyond workflow hookup

**Typical inputs/outputs**
- emits events
- stores code and collaboration state
- receives branch/PR proposals

### 2.2 Trigger / Task Gateway / Orchestration Adapter Layer
**Responsibilities**
- receive forge or other source events
- normalize them into a stable task request contract
- apply intake policy
- route tasks to the correct execution profile
- keep event-source specifics out of downstream layers

**Should not own**
- repo truth
- direct code execution
- CI verification
- deploy actions

**Key design requirement**
This layer should remain under project control and should not be irreversibly coupled to a single forge or a single agent runtime.

### 2.3 Context / Policy Layer
**Responsibilities**
- repository rules
- task policies
- branch/approval rules
- allowed command constraints
- reusable workflow instructions
- definition-of-done style constraints

**Should not own**
- the full runtime execution engine
- forge state
- CI verdicts

**Key design requirement**
Durable policy should not exist only in ephemeral prompts.

### 2.4 Agent Control Plane Layer
**Responsibilities**
- start agent sessions
- assemble session context
- attach tool/skill sets
- track agent execution state
- coordinate handoff to runtime layer

**Should not own**
- forge source-of-truth state
- CI verdict authority
- release/deploy control

**Key design requirement**
This layer may use a specific agent product initially, but its responsibility should be framed abstractly enough to allow replacement later.

### 2.5 Execution Runtime Layer
**Responsibilities**
- workspace preparation
- checkout/mount code
- bounded file edits
- test/lint/build execution
- patch/commit preparation

**Should not own**
- policy definition
- issue tracking semantics
- final verification authority

**Key design requirement**
Runtime should be isolated from the host environment by default.

### 2.6 Verification / CI Layer
**Responsibilities**
- build/test/lint/scan verification
- independent pass/fail signal
- repeatable validation logic

**Should not own**
- agent planning
- durable policy authoring
- deploy authority by default

**Key design requirement**
CI acts as an independent verifier, not merely as agent-owned tooling.

### 2.7 Deploy / Release Layer
**Responsibilities**
- release packaging and promotion
- environment deployment
- release approval gates
- operational rollout control

**Should not own**
- general coding-agent planning
- task intake normalization

**Key design requirement**
Deploy should remain separate from agent execution, especially in early phases.

## 3. Source of Truth Guidance
### Durable source of truth should live in:
- forge/repo content for code and collaboration state
- repository docs for architecture, roadmap, WBS, policy, and decisions
- CI definitions for objective validation behavior

### Durable source of truth should not live only in:
- transient chat context
- a single agent's internal memory
- undocumented workflow conventions

## 4. Replaceability Targets
The system should aim to preserve replaceability at these seams:
- forge/PM provider
- task intake adapter
- agent control implementation
- isolated runtime implementation
- CI engine
- deploy/release engine

## 5. Anti-Patterns to Avoid
- directly encoding source-specific event semantics deep inside the agent
- mixing CI verification with agent authority
- letting deployment become an accidental side effect of code generation
- using prompts as the only durable workflow definition
- binding architecture boundaries to a single vendor's product shape

## 6. Near-Term Boundary Focus
In early phases, the most important boundaries to defend are:
- trigger/task gateway vs agent control
- context/policy vs prompt-only behavior
- agent runtime vs CI
- CI vs deploy
