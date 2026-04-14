# ADR-0001: System Boundaries for the Agent-Oriented SDLC Platform

- Status: Accepted (initial baseline)
- Date: 2026-04-13

## Context
The project aims to create an issue-driven or event-driven agent-assisted SDLC workflow. The desired experience resembles modern integrated coding assistants, but the project must preserve architecture clarity and future replaceability.

Without explicit boundaries, the system risks collapsing into a single-tool workflow where:
- forge events are tightly coupled to agent logic
- durable policy lives only in prompts
- CI becomes a thin afterthought rather than an independent verifier
- deployment becomes an accidental side effect of code generation

## Decision
The system will be designed with explicit boundaries between:
1. Forge / PM
2. Trigger / Task Gateway / Orchestration Adapter
3. Context / Policy
4. Agent Control Plane
5. Execution Runtime
6. Verification / CI
7. Deploy / Release

## Rationale

### 1. Orchestration should not be irreversibly bound to a forge
The trigger/task gateway boundary allows the system to:
- normalize source-specific events
- change forge vendors later
- support more than one source type over time

### 2. Durable policy should not live only in prompts
Policies, rules, and operating expectations should be documented and/or externalized so they remain reviewable and governable.

### 3. CI must remain an independent verifier
The same agent that proposes a change should not be the sole judge of its quality or correctness.

### 4. Deploy and release remain separate responsibilities
Code generation and release control have different risk profiles and should not be merged by default.

### 5. Execution runtime should be isolated
Agent work may involve file changes and command execution. Isolation reduces coupling and risk.

## Consequences
### Positive
- clearer replacement paths
- stronger governance
- easier review of decisions and policies
- better long-term maintainability

### Negative
- more upfront structure
- slightly more coordination overhead in early design
- slower initial implementation if boundaries are over-engineered

## Follow-Up
Future ADRs should refine:
- first implementation target choices
- policy representation model
- runtime isolation strategy
- task request contract
