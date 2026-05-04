# Project Overview

## 1. Problem Statement
The project aims to build an **agent-oriented SDLC system** that feels close to modern issue-driven coding assistants, while keeping the architecture clearly layered and replaceable.

The desired top-level experience is:

`issue / comment / label -> task intake -> agent execution -> code proposal -> PR -> CI -> human review / merge`

The key design constraint is that this experience should **not** depend on a single vendor-specific control plane or a single tool's internal workflow model.

## 2. Goals
- Provide an issue-driven or event-driven agent workflow.
- Preserve clear system boundaries so components can be replaced later.
- Externalize durable policy, workflow rules, and governance logic.
- Keep CI independent as the objective verifier.
- Keep deployment responsibility separate from the agent runtime.
- Establish a repository baseline that future agents can maintain safely.

## 3. Non-Goals
- Building a fully complete platform in the first iteration.
- Giving the agent direct production deployment control by default.
- Hard-coding the system around one forge, one agent, or one CI vendor.
- Storing all durable workflow logic only inside prompt text.

## 4. Target Users
### Primary
- maintainers of an internal or self-hosted SDLC automation platform
- developers who want issue-to-PR agent assistance
- technical owners who need architecture clarity and change governance

### Secondary
- reviewers who need traceable AI-originated changes
- platform engineers who may replace or extend forge/CI/runner layers later

## 5. Core Use Cases
1. A user labels or comments on an issue to request agent work.
2. The system normalizes that event into a task request.
3. An agent session starts with the right context and policy pack.
4. The agent proposes a change in an isolated runtime.
5. The change is surfaced as a branch/PR.
6. CI validates the change independently.
7. A human decides whether to merge.

## 6. Design Principles
1. **Experience and architecture are different concerns.**
   The user-facing experience may look unified, but the internal system should remain layered.

2. **Workflow logic should be governable.**
   Policy, rules, and lifecycle definitions should be documented and, where practical, externalized.

3. **Replaceability matters.**
   Forge, agent runtime, CI, and deploy layers should be replaceable with bounded refactoring.

4. **Verification must be independent.**
   The same agent that proposes a change should not be the sole judge of its correctness.

5. **Deploy is not the same as code generation.**
   Release control remains a separate responsibility.

## 7. Constraints
- Early phases should minimize premature implementation.
- The repo should act as persistent memory for future agent runs.
- Planning documents must stay maintainable over time.
- Roadmap and WBS should be AI-updatable, but format-stable.

## 8. Initial Architecture View
The project is expected to separate at least these layers:
- Forge / PM layer
- Trigger / Task Gateway / Orchestration Adapter layer
- Context / Policy layer
- Agent Control Plane layer
- Execution Runtime layer
- Verification / CI layer
- Deploy / Release layer

See `docs/architecture/overview.md` for details.

## 9. Open Questions
The first Phase 1 target choices for forge, policy representation, runtime isolation, and minimum CI gating are now documented in ADR-0002, ADR-0003, and the Phase 1 design specs.

Remaining higher-level questions include:
- How much of task routing should live in repo config versus service config?
- What observability beyond minimum traceability should remain deferred until Phase 2?
- When should the runtime move from the first host-local container runner to a remote worker model?

## 10. Success Criteria for This Repository Baseline
This initialization baseline is successful if it provides:
- a stable architecture narrative
- a maintainable roadmap and WBS
- explicit governance rules
- a durable user capability matrix that explains what users can trigger where and how that maps to the current workflow
- reusable initialization prompt(s)
- enough structure for future implementation work without forcing a premature design lock-in
