# Runtime Isolation

## Purpose
This document defines the first runtime isolation strategy for bounded agent execution.

It refines the Execution Runtime layer in `docs/architecture/overview.md` and follows ADR-0002.

## 1. Goals
- isolate agent execution from the host environment by default
- make runtime capabilities explicit enough for policy enforcement
- preserve disposable worker behavior for the minimum closed loop
- keep runtime separate from CI and deploy responsibilities

## 2. Non-Goals
- selecting the final long-term worker platform
- solving multi-tenant scheduling in Phase 1
- granting direct deploy authority to the runtime

## 3. Phase 1 Isolation Strategy
Phase 1 uses an ephemeral container-based worker per task/session.

This means:
- each accepted task runs in its own isolated container or equivalent isolated worker instance
- the worker is created for the session and removed after completion
- only explicit artifacts survive the session boundary

## 4. Boundary Decisions

### 4.1 Isolation Unit
- one worker per task/session
- no shared long-lived mutable runtime across unrelated tasks by default

### 4.2 Workspace Strategy
- prepare a fresh repository checkout or equivalent session-local workspace inside the worker
- avoid binding the host developer workspace as the primary execution surface

### 4.3 Privilege Model
- run as a non-root user by default
- do not expose the host Docker socket or equivalent host-control interface
- do not grant runtime access beyond the selected capability set

### 4.4 Network Model
- restricted by default
- allow only the network paths needed for the supported workflow
- do not assume unrestricted access to internal or production systems

### 4.5 Secret Model
- inject only the minimum secrets required for the selected workflow
- do not treat all sessions as secret-bearing
- prefer short-lived or narrowly scoped credentials when available

### 4.6 Artifact Boundary
Allowed outputs should be explicit and may include:
- change proposals or patch artifacts
- logs
- test or build outputs
- machine-readable task/session metadata

The worker container itself should not be treated as the durable record.

### 4.7 Cleanup
- remove the worker after completion or failure
- preserve only approved artifacts and traceability metadata

## 5. Responsibilities by Layer

### Agent Control Plane
- starts and tracks the worker lifecycle
- passes the selected capability set into runtime

### Execution Runtime
- enforces the bounded execution environment
- prepares the workspace
- produces artifacts and status

### CI
- validates the resulting proposal independently

## 6. Phase 1 Practical Defaults
Unless a later decision overrides them, Phase 1 should assume:
- containerized worker
- non-root execution
- session-local checkout
- restricted egress
- minimal secret injection
- explicit artifact export

## 7. Open Questions
- which container runner should be used first?
- what exact network destinations must be allowed for the first closed loop?
- how should dependency caching be handled without weakening isolation too far?
