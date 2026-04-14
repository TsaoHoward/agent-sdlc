# System Context

## Purpose
This document describes the system from the outside: main actors, external systems, and interaction boundaries.

## Core Actors
### Human Maintainer / Developer
- creates or manages issues
- reviews PRs
- approves architecture and release decisions

### Agent-Oriented SDLC System
- accepts normalized tasks
- runs bounded agent sessions
- proposes code changes
- reports status

### CI System
- validates proposed changes independently

### Deploy/Release System
- promotes and deploys approved changes

## External/Adjacent Systems
### Forge / PM Platform
Examples: GitHub, Gitea, Forgejo, GitLab, or equivalent.

Provides:
- repositories
- issues
- PRs
- comments
- labels
- webhook/event surface

### Agent Runtime Product or Framework
Examples: OpenHands-like control plane, Codex-like coding agent, Goose-like orchestration shell, or a custom wrapper.

Provides:
- agent session orchestration
- tool integration
- model/runtime control

### Isolated Worker Infrastructure
Examples:
- Docker containers
- remote workers
- Kubernetes jobs

Provides:
- safe execution boundary for agent actions

### Policy / Configuration Sources
May include:
- repo docs
- config files
- service config
- policy packs

## Context Diagram (Textual)
- Humans interact with the Forge / PM platform.
- Forge / PM emits events into the Task Gateway.
- Task Gateway normalizes events and consults policy/context.
- Task Gateway starts or routes work to the Agent Control Plane.
- Agent Control Plane runs work in an isolated Execution Runtime.
- Proposed changes are surfaced back to the Forge.
- CI validates proposed changes independently.
- Release/deploy processes remain downstream and separate.

## Boundary Notes
- The Task Gateway shields the rest of the system from source-specific event formats.
- The Agent Control Plane should not become the primary source of truth.
- The Execution Runtime should be treated as disposable and isolated.
- CI and Deploy remain separate systems, even if triggered by forge workflows.
