# ADR-0006: Platform Implementation Stack and Packaging Baseline

- Status: Accepted
- Date: 2026-04-15

## Context
The project has already selected its Phase 1 architectural boundaries, first forge target, policy representation, runtime isolation model, and early trigger path.

Implementation is now moving from planning into WBS 3, where the repository needs a clearer answer to these cross-cutting questions:
- which language and runtime should the platform's own control-plane logic converge on?
- which repo surfaces should remain multi-format by design?
- how should local bootstrap scripts relate to the long-term self-hosted packaging target?
- how should container packaging be represented without turning a deployment format into a hidden architecture decision?

Without an explicit baseline, the project risks:
- splitting the platform's core implementation across too many languages
- treating temporary bootstrap scripts as the de facto long-term control-plane model
- delaying dependency and packaging discipline until after the service topology is harder to change
- conflating the platform's implementation stack with the many languages that target repositories may use inside worker sessions

## Decision
The platform implementation and packaging baseline is:

1. The platform's core control-plane and orchestration logic should converge on `TypeScript` running on `Node.js LTS`.
2. Platform-managed Node-based code should be managed through `npm`, including a repo-owned `package.json` and lockfile when that layer becomes a formal package.
3. Durable docs, policy, and config remain intentionally split across `Markdown`, `YAML`, and `JSON`.
4. Early operator-facing local bootstrap wrappers may remain in `PowerShell` while the repository is still Windows-first and Phase 1 focused.
5. Repo-owned container definitions should become the durable packaging surface for platform services and worker runtime images:
   - at least one control-plane image
   - at least one worker runtime image
6. `docker compose` is the preferred near-term self-hosted packaging target once the service topology is stable enough to justify consolidation.
7. `docker compose` is a deployment/package surface, not an architecture boundary or source of truth for workflow ownership.

## Decision Details

### 1. Platform Stack Versus Target-Repository Stack
This decision applies to the SDLC platform itself:
- task gateway
- agent control
- proposal/traceability support services when they become serviceized
- related platform packaging

It does not require target repositories executed by workers to use the same language. Worker tasks may still operate on repositories that use other languages and toolchains.

### 2. TypeScript / Node.js As The Platform Core
The repository already has early Node.js-based control-host scaffolds for WBS `3.1` and `3.2`.

Phase 1 may continue to use plain JavaScript for very early slices when that keeps momentum high, but the selected convergence path is:
- Node.js LTS runtime
- TypeScript for growing platform code
- npm as the package and script surface

This gives the project:
- one main application stack for control-plane growth
- good support for JSON/YAML/webhook/CLI workflows
- a straightforward path into local development, testing, service containers, and future HTTP APIs

### 3. Intentional Multi-Format Repo Surfaces
Some repository surfaces are intentionally not part of the platform's application-language convergence:
- `docs/` stays in Markdown
- `config/` policy and service config may stay in YAML/JSON
- CI definitions may stay in forge- or runner-native workflow YAML

This is not stack drift. It reflects different ownership and review needs.

### 4. PowerShell Scope
PowerShell remains acceptable for:
- Windows-first local bootstrap
- operator convenience wrappers
- environment bring-up helpers

PowerShell should not become the primary long-term home of the growing control-plane business logic if the Node/TypeScript platform stack is already available.

### 5. Packaging Baseline
The repository should move toward repo-owned container packaging in two layers:

#### Control-Plane Packaging
- a repo-owned Dockerfile for the platform control-plane or its first combined service image

#### Worker Packaging
- a repo-owned Dockerfile for the first worker runtime image used by WBS `3.3`

These images should remain distinct enough that:
- worker isolation stays explicit
- control-plane and runtime responsibilities do not collapse together

### 6. Compose Role
The preferred near-term self-hosted packaging target is a repository-owned `docker compose` package once the active service mix is stable.

The expected compose package may eventually include services such as:
- Gitea
- PostgreSQL
- platform control-plane service(s)
- worker-runtime launcher or related helper service(s) if needed
- optional reverse proxy or runner attachments

The compose file should package the chosen service topology, not define the architecture itself.

## Rationale

### Why Converge The Platform Core On One Main Stack
- reduces implementation sprawl
- makes dependency management and testing more coherent
- gives WBS `3.x` a clearer development path

### Why Keep Docs And Policy Multi-Format
- docs, policy, CI, and machine-readable config have different review and ownership needs
- forcing everything into application code would weaken governance clarity

### Why Keep PowerShell For Bootstrap
- current operator flow is Windows-first
- local bring-up wrappers are not the same thing as the platform's main service implementation

### Why Require Repo-Owned Dockerfiles Before Compose Consolidation
- keeps packaging reviewable and versioned in the repository
- prevents the final packaging target from depending on undocumented local environment setup
- makes worker/runtime boundaries concrete before higher-level orchestration is flattened into compose

## Consequences

### Positive
- the platform now has a clear primary implementation stack
- the next WBS slices can add `package.json`, TypeScript migration, and Dockerfiles without reopening the stack question
- self-hosted packaging has a defined direction without prematurely collapsing architecture into one compose file

### Negative
- the repository will temporarily carry both PowerShell and Node/TypeScript surfaces
- the current JavaScript scaffolds will need either incremental TypeScript migration or a consciously bounded exception during early slices
- compose packaging remains deferred until the service topology is concrete enough

## Follow-Up
This ADR should drive the following near-term work:
- add a repo-owned Node package baseline for platform code
- use that baseline for growing control-plane logic
- add the first worker-runtime Dockerfile under WBS `3.3`
- add a control-plane Dockerfile when the current CLI scaffolds are ready to be packaged as a service image
- revisit `docker compose` packaging after the service topology for forge, control-plane, worker runtime, and state surfaces is no longer speculative
