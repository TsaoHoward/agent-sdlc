# D-012: Phase 1 Minimal Real Agent Execution Shape

## Purpose
This document is the supporting analysis note for decision backlog item `D-012`.

It narrows the first real AI execution slice for WBS `3.9` without silently changing the repository's architecture boundaries.

## Decision Scope
This note focuses on the first Phase 1 AI-backed execution path for a single supported task class.

It covers:
- whether the project should use a provider-hosted agent product, a direct model API, or a local model runtime as the first execution path
- where the provider integration should attach to the current task/session/runtime/proposal flow
- what minimum tool surface and evidence should exist for the first real execution slice

It does not cover:
- Phase 2 multi-agent orchestration
- broader intake expansion beyond the current issue-comment path
- replacing the current repo-owned runtime, traceability, CI, or proposal surfaces

## Current Repository Constraints
As of 2026-04-22, the repository already owns and implements these boundaries:
- task intake and policy resolution in `scripts/task-gateway.js`
- session creation in `scripts/agent-control.js`
- runtime workspace preparation in `scripts/lib/runtime-launcher.js`
- proposal creation in `scripts/proposal-surface.js`
- CI and review-linked traceability outside the agent runtime

The current implementation gap is narrower than "add AI somewhere":
- the runtime already prepares a per-session workspace
- the system already creates proposal PRs and independent CI runs
- the missing step is a real provider-backed execution stage between `workspace-prepared` and proposal surfacing

This matters because the first AI integration should fit the existing architecture:
- task gateway should still own task classification and approval
- agent control should still own session start and context assembly
- runtime should still own file and command execution
- CI should still remain the independent verifier

## Goals
- satisfy WBS `3.9` with one real AI-generated repository-change path
- preserve replaceability across provider, model, and hosting choices
- keep the first slice narrow enough to validate quickly
- keep durable traceability and review surfaces repo-owned

## Non-Goals
- selecting the final long-term agent platform for every future phase
- turning Phase 1 into a generalized hosted-agent control plane
- adding broad task autonomy before the first bounded slice is proven

## External Inputs Verified On 2026-04-22
These external references were checked to avoid relying on stale product assumptions:

- OpenAI documents the `Responses API` as the current core API primitive for generating responses and using built-in tools:
  - https://developers.openai.com/api/reference/overview
  - https://openai.com/index/new-tools-and-features-in-the-responses-api/
- OpenAI documents the `Agents SDK` as the layer to use when the application owns orchestration, tool execution, approvals, and state:
  - https://developers.openai.com/api/docs/guides/agents
- OpenAI documents that the `Assistants API` is deprecated and scheduled to shut down on `August 26, 2026`:
  - https://developers.openai.com/api/docs/assistants/tools
- Ollama documents a local API at `http://localhost:11434/api`, optional cloud access through `https://ollama.com/api`, and partial OpenAI-API compatibility:
  - https://docs.ollama.com/api/introduction
  - https://docs.ollama.com/api/authentication
  - https://docs.ollama.com/api/openai-compatibility

These references inform the recommendation below. They do not override repository architecture or governance documents.

## Decision Surfaces

### 1. Orchestration Ownership

#### Option A - Provider-Hosted Agent As The Primary Runtime
Examples:
- a provider-native hosted agent workflow
- a provider-native sandbox becoming the main execution surface

Pros:
- fastest path to sophisticated tool-using behavior
- less repo-owned execution orchestration to build initially

Cons:
- overlaps with the repository's existing agent-control and runtime boundaries
- risks making provider session state or provider sandbox behavior the de facto source of truth
- raises a stronger ADR-level boundary question immediately

Assessment:
- poor fit for the current Phase 1 architecture because the repo already owns session start, runtime preparation, proposal creation, and traceability

#### Option B - Repo-Owned Orchestration With Provider Model API
Examples:
- the repo keeps session/runtime ownership
- a provider API is called from the prepared workspace to plan and generate bounded edits
- repo-owned code executes file changes and allowed commands

Pros:
- best fit for the current architecture
- keeps provider choice behind an adapter boundary
- preserves repo-owned traceability, proposal, and CI responsibilities

Cons:
- requires some repo-owned execution-loop implementation
- tool and file-edit behavior must be defined explicitly

Assessment:
- best fit for the current repository and the safest Phase 1 default

#### Option C - Repo-Owned Orchestration With Local-Only Model Runtime
Examples:
- local model served through Ollama
- local inference becomes the only supported first provider

Pros:
- strongest local control and privacy posture
- lowest external API dependency once running

Cons:
- higher hardware and model-quality variability
- weaker default reproducibility across operators
- higher risk that Phase 1 stalls on model/runtime tuning instead of validating workflow boundaries

Assessment:
- useful as a compatibility target, but high-risk as the only first-path default

### Recommendation For Orchestration Ownership
Choose `Option B - Repo-Owned Orchestration With Provider Model API` for the first slice.

This keeps the existing boundary model intact:
- provider handles model inference
- the repository still owns orchestration, file execution, traceability, proposal creation, and CI

## 2. API Surface Choice For The First Remote Provider

### Option A - OpenAI Responses API
Pros:
- current primary OpenAI API surface for agentic applications
- supports tool use and structured app-owned orchestration
- does not require adopting a provider-hosted workflow editor or hosted session model

Cons:
- the repo must still build its own execution loop and tool wrappers

Assessment:
- best-fit OpenAI surface for the current architecture

### Option B - OpenAI Agents SDK As The First Integration Layer
Pros:
- good support for tool-using, multi-step agents
- sandbox and state features are available in the SDK direction

Cons:
- overlaps with the repo's current runtime and session-control responsibilities
- risks introducing a second runtime/orchestration abstraction before the first slice is proven

Assessment:
- promising later option, but not the cleanest first slice while repo-owned runtime is already present

### Option C - OpenAI Assistants API
Assessment:
- should not be chosen for new work
- official docs currently mark it deprecated and scheduled to shut down on `August 26, 2026`

### Recommendation For OpenAI Surface
If OpenAI is chosen as the first remote provider, use the `Responses API`, not the `Assistants API`.

Treat the `Agents SDK` as a later-phase option to revisit only if the project decides that provider-native sandbox/state patterns should supplement or replace parts of the current repo-owned runtime model.

## 3. Hosting Mode Choice

### Option A - Remote API First
Pros:
- fastest way to prove the workflow with strong model capability
- lower local setup burden for maintainers
- cleaner validation of whether WBS `3.9` is a workflow problem or a model-quality problem

Cons:
- requires API key management
- depends on network availability
- introduces usage cost

### Option B - Local Runtime First
Pros:
- no required external API for the first slice once installed
- stronger local privacy posture

Cons:
- depends on operator hardware and downloaded model quality
- harder to make "works on maintainer machine" reproducible
- more likely to conflate workflow risk with local-model quality risk

### Option C - Hybrid Adapter: Remote First, Local-Compatible
Pros:
- keeps the first slice practical
- preserves a path to later local execution
- allows the same high-level contract to target OpenAI or Ollama-style backends

Cons:
- requires one adapter seam up front
- slightly more implementation work than hard-coding one provider call

### Recommendation For Hosting Mode
Choose `Option C - Hybrid Adapter: Remote First, Local-Compatible`.

Concrete Phase 1 default:
- first supported provider path: remote API
- first compatibility target after the initial slice proves out: local runtime through an adapter such as Ollama's OpenAI-compatible surface or native Ollama API

This avoids locking the architecture to either SaaS-only or local-only operation.

## 4. First Task Class Choice

### Option A - `documentation_update`
Pros:
- simplest task to make succeed quickly
- low risk

Cons:
- does not fully satisfy the stated intent behind WBS `3.9`, which explicitly expects the first validated path to start with `bounded_code_change`
- may prove the model call but not the more valuable bounded change path

### Option B - `bounded_code_change`
Pros:
- aligns directly with WBS `3.9`
- validates the more meaningful end-to-end path
- proves that the AI slice can create repository changes worth reviewing

Cons:
- requires tighter guardrails on files, commands, and completion criteria

### Recommendation For First Task Class
Choose `bounded_code_change` as the first supported task class, but narrow it operationally:
- one bounded prompt shape
- one bounded file scope or issue-driven change scope
- one bounded command allowlist
- one bounded validation path

If a lower-risk dress rehearsal is needed, the same execution adapter may later be reused for `documentation_update`, but that should not replace the Phase 1 target.

## 5. Tool And Execution Surface

### Option A - Let The Provider Own Tools And Sandbox
Assessment:
- poor fit for the current repo architecture in Phase 1

### Option B - Keep Tools Repo-Owned And Pass Them Through A Thin Agent Adapter
Recommended minimum tool surface:
- read files from the prepared workspace
- write or patch files in the prepared workspace
- list files and inspect diffs
- run a short allowlisted command set tied to the selected runtime capability set
- emit a structured execution summary

Why this shape is preferred:
- it matches the current runtime boundary
- it keeps capability enforcement local and reviewable
- it avoids duplicating sandbox or traceability concerns inside a provider SDK

## Recommended Phase 1 Shape

### Summary
The best first slice is:
- repo-owned orchestration
- repo-owned runtime and tool execution
- remote API first
- provider adapter boundary from day one
- first remote default via `DeepSeek API`
- local compatibility path reserved for a later Ollama-backed adapter
- first supported task class: `bounded_code_change`

### Proposed Integration Boundary
Add a provider-neutral execution step after workspace preparation and before proposal creation.

Suggested logical contract:

```text
agent-control start-session
  -> runtime-launcher prepares workspace
  -> agent-execution runner executes bounded AI loop in that workspace
  -> session record captures execution result and evidence
  -> proposal-surface creates PR from resulting workspace
```

Suggested repository-owned adapter boundary:

```text
executeAgentSlice({
  taskRequest,
  sessionRecord,
  workspaceDir,
  runtimeCapabilitySet,
  contextRefs
}) -> {
  status,
  summary,
  changedFiles,
  validationCommandsRun,
  providerRef,
  providerResponseRefs,
  finishedAt
}
```

### Why This Boundary Fits
- `task-gateway` still owns classification and approval
- `agent-control` still owns session lifecycle
- `runtime-launcher` still owns isolated workspace creation
- `proposal-surface` still owns branch/PR surfacing
- CI still remains the independent verifier

## Evidence Expectations For The First Slice
The first AI-backed execution path should write durable evidence beyond transient logs.

Minimum recommended evidence:
- execution status in the session record
- provider name and model identifier
- provider request/response correlation IDs when available
- files changed
- commands attempted and exit status
- short agent-produced summary
- failure reason taxonomy when generation or execution fails

This evidence should remain repo-owned even if the model call is remote.

## Proposed Selection Matrix
| Direction | Architecture Fit | Implementation Speed | Replaceability | Local Reproducibility | Recommendation |
|---|---|---|---|---|---|
| Provider-hosted agent as primary runtime | Low | Medium | Low | Medium | No |
| Repo-owned runtime plus remote model API | High | High | High | High | Yes |
| Local-only model runtime first | Medium | Low | Medium | Low | Not as first default |
| Hybrid adapter with remote-first default | High | Medium | High | High | Yes |

## ADR Trigger Check
At this analysis stage, no ADR is required yet if the selected direction stays within the current architecture:
- repo keeps orchestration ownership
- repo keeps runtime ownership
- repo keeps CI and traceability ownership
- provider stays behind an adapter

An ADR should be created before implementation if the chosen direction changes any of these:
- provider sandbox becomes the primary runtime boundary
- provider-managed session state becomes durable truth
- CI or proposal responsibility moves into provider-owned workflow
- secrets, approvals, or policy enforcement shift materially out of repo-owned layers

## Recommended Next Implementation Slice
1. Add a provider-neutral `agent execution runner` inside the current `agent-control` to `runtime` handoff.
2. Implement one remote-provider adapter first.
3. Keep the first prompt and tool loop intentionally narrow for `bounded_code_change`.
4. Extend session and traceability records with execution evidence before proposal creation.
5. Re-run `TC-001`, `TC-002`, and `TC-003`, then add or update test coverage for the first real AI execution path.

## Open Questions
- Which exact model should be the default for `bounded_code_change` in Phase 1?
- Should the first slice allow network access during execution beyond model-provider access and repo package install needs?
- Should the first slice allow iterative command execution, or require one propose-edit-validate cycle only?
- What is the maximum file-count or directory-scope boundary for the first `bounded_code_change` request?

## Working Recommendation
Unless a later review surfaces a new boundary concern, the recommended path is:
- keep orchestration and runtime repo-owned
- use a provider model API, not a provider-hosted agent workflow, for the first slice
- prefer `Responses API` if OpenAI is selected
- avoid starting new work on the deprecated `Assistants API`
- keep a later-compatible adapter path for local execution through Ollama
- target `bounded_code_change` as the first real task class

## Selected Direction On 2026-04-22
The current selected direction is:
- long-term execution posture: support both remote and local model backends
- backend switching: through a repo-owned API adapter boundary plus configuration, not by rewriting workflow logic
- short-term remote default: `DeepSeek API`
- first execution mode to land: remote API first
- later compatibility target: preserve a local-backend path such as Ollama behind the same adapter shape

## Selected Defaults

### Backend Strategy
The model backend should be selected by repo-owned configuration behind one execution adapter shape.

That means:
- task gateway, agent control, runtime, proposal, and CI stay repo-owned
- the configured backend changes which model endpoint is used
- provider choice should not be embedded as hidden orchestration logic inside session startup or proposal flow

### Remote And Local Compatibility
The project should not treat remote and local execution as different workflow architectures.

Instead:
- the workflow stays the same
- only the configured backend adapter changes
- the remote provider path is used first to get WBS `3.9` landed quickly
- local compatibility remains a first-class design target so the project can later run against a local endpoint without redesigning the control-plane flow

### Short-Term Provider Default
The first remote provider default is `DeepSeek API`.

This means the first implementation slice should optimize for:
- a DeepSeek-backed remote adapter
- configuration-driven provider selection
- evidence fields that record the chosen provider and model in session output

### OpenAI Status Under The Selected Direction
OpenAI remains a relevant compatibility target, and the earlier analysis about `Responses API` versus deprecated `Assistants API` still matters if an OpenAI adapter is added later.

However, OpenAI is no longer the short-term default for WBS `3.9`.

### Configuration Guidance
The first implementation slice should prefer a repo-owned configuration surface for backend selection rather than embedding provider choice only in code.

Minimum desired behavior:
- choose backend type from config
- choose mode from config
- choose base URL from config
- choose model identifier from config
- keep secrets outside checked-in config, passed by environment or equivalent secret surface

Illustrative shape only:

```yaml
agentExecution:
  backend: deepseek
  mode: remote
  baseUrl: https://api.deepseek.com
  model: <selected-model>
```

This example is intentionally illustrative. It records the desired control shape, not a finalized schema.

## Implementation Defaults Selected On 2026-04-23
The first implementation slice settled these detail defaults without changing the selected architecture:
- checked-in config template path: `config/agent-execution.template.yaml`
- generated local config path: `config/agent-execution.yaml`, ignored by Git
- default backend: `deepseek`
- default mode: `remote`
- default base URL: `https://api.deepseek.com`
- default model identifier: `deepseek-chat`
- API key environment variable: `DEEPSEEK_API_KEY`
- default activation posture: disabled unless explicitly enabled through config or `AGENT_SDLC_AGENT_EXECUTION_ENABLED`
- first evidence artifact: `agent-execution.json` in the session artifact directory, referenced from the session record

This keeps the provider and model choice visible while avoiding a hard dependency on API credentials for the already-working local closed-loop scaffold.
The local config can be generated from the template with `npm run dev:agent-execution-config`.

## Implications For WBS 3.9
The first implementation slice should now be understood as:
- one repo-owned execution adapter contract
- one DeepSeek-backed remote implementation
- one config-selected backend surface designed so a later local backend can plug in without changing task-gateway, proposal, or CI ownership

## ADR Trigger Check After Selection
This selected direction still does not require an ADR by itself because it does not change the current architecture boundaries:
- the repo still owns orchestration
- the repo still owns runtime and proposal flow
- the repo still owns traceability and CI linkage
- provider selection remains an implementation-facing adapter choice behind the current architecture

An ADR is still required before implementation only if the project later decides to:
- move durable session state into a provider-managed service
- make a provider sandbox the primary runtime boundary
- move proposal or verification authority into provider-managed workflow

## Remaining Detail Questions
The major direction is now selected, but these detail choices remain for implementation:
- provider-enabled validation with a real `DEEPSEEK_API_KEY`
- whether the first execution loop should stay one-shot generate-edit-validate or allow a small bounded iteration count
- the first local-backend adapter target and whether it should use Ollama's native API or an OpenAI-compatible endpoint
