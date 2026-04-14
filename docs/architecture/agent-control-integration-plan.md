# Agent Control Integration Plan

## Purpose
This document defines the first concrete integration shape for the Agent Control Plane.

It is the design deliverable for WBS `2.2` and follows ADR-0002.

## 1. Goals
- keep task gateway and agent control as separate layers
- give Phase 1 a simple session-start path
- define enough session state to support traceability and review
- avoid coupling the integration plan to one agent product's internal abstractions

## 2. Non-Goals
- designing a queue-based orchestration platform for later phases
- defining every agent runtime-specific tool or prompt detail
- replacing the task gateway with agent-launch logic

## 3. Phase 1 Decision
Phase 1 uses a `direct session starter interface`.

This means:
- task gateway resolves and emits a normalized task request
- task gateway calls an agent-control session starter with that normalized request
- agent control creates an `agent_session_id`, assembles context, and hands off to runtime

## 4. Boundary Rule
The task gateway decides:
- task acceptance
- policy/profile selection
- whether execution is allowed

The agent control plane decides:
- how a permitted session is started
- how session context is assembled
- how runtime handoff and session state are tracked

The task gateway must not embed agent-specific launch logic as its primary control model.

## 5. Session Starter Contract
The Phase 1 session starter should accept at least:
- normalized task request
- resolved execution profile and runtime capability references
- policy and ADR references needed for context assembly

The session starter should return at least:
- `agent_session_id`
- session status
- runtime handoff status or failure reason
- timestamps for session start

## 6. Minimum Session State Model
Phase 1 should track at least these session states:
- `pending`
- `starting`
- `running`
- `completed`
- `failed`
- `cancelled`

## 7. Context Assembly Requirements
Before runtime handoff, agent control should assemble:
- repository context references
- relevant roadmap and WBS references when applicable
- policy references
- task and traceability identifiers
- allowed capability references

Context assembly should use durable repo sources where available rather than relying on transient chat state.

## 8. Persistence Guidance
Phase 1 should preserve a machine-readable session record that includes:
- `agent_session_id`
- `task_request_id`
- session state
- runtime capability set reference
- session timestamps
- artifact references when available

This record does not require a separate service database in Phase 1, but it must survive beyond in-memory runtime state.

## 9. Future Evolution Path
The direct session starter interface should be designed so it can later move behind:
- an internal queue
- a workflow engine
- a remote control service

The contract should be stable enough that downstream runtime and proposal logic do not depend on whether startup is direct or queued.

## 10. Open Questions
- what is the exact session-starter interface shape: CLI, API, or internal module boundary?
- where should the first session record be stored?
- what minimum failure taxonomy should be preserved in Phase 1?
