# Agent-First SDLC Bootstrap

## Purpose
This repository is the initialization baseline for an agent-oriented SDLC system.

The target user experience is:

`issue -> task intake -> agent session -> code change -> branch/PR -> CI verification -> human review/merge`

The target architecture is deliberately layered so the system can evolve without being locked to a single forge, agent runtime, CI stack, or deployment mechanism.

## Current Status
This repository is in **early Phase 1 implementation** state.

The repo is no longer planning-only. It now has a working minimum closed-loop scaffold across the main Phase 1 layers:
- repo-owned local Gitea bootstrap with a default local repo path
- webhook-backed task intake from issue comments
- file-backed task and session records under `.agent-sdlc/state/`
- isolated worker-runtime handoff into per-session workspaces
- proposal surfacing as branch plus PR
- local Gitea Actions verification with traceability metadata
- reviewer-facing traceability that now extends through explicit review outcomes

The goal is still **not** to deliver the full platform immediately. The current focus is to harden the smallest useful issue-driven experience without collapsing architecture boundaries.

## Progress Against Target Experience
Target experience:

`issue -> task intake -> agent session -> code change -> branch/PR -> CI verification -> human review/merge`

Current progress:
- `issue -> task intake`: working through the Gitea issue-comment webhook path and file-backed replay examples
- `task intake -> agent session`: working for auto-approved Phase 1 task classes
- `agent session -> code change -> branch/PR`: working through the worker-runtime scaffold plus proposal surface
- `branch/PR -> CI verification`: working on the local Gitea Actions stack, including restored PR-triggered runs and branch-local dispatch fallback
- `CI verification -> human review`: working with reviewer-facing PR traceability updates
- `human review -> review outcome traceability`: working, including explicit sync of Gitea review decisions back into durable traceability and the PR body
- `review follow-up automation`: working through a default bootstrap-managed review webhook plus event-driven replay/sync entrypoints

## Current Todo
- validate the fully bootstrapped local happy path end to end from issue comment through review webhook without manual patch-up steps
- improve operator-facing artifact browsing or listing now that traceability, CI metadata, and review sync are in place
- decide how much more of the local operator workflow should be consolidated into the default bootstrap before moving on to broader Phase 2 concerns
- keep the Phase 1 slice narrow and avoid pulling in broader observability, multi-source intake, or deployment concerns too early

## Source of Truth
Use these files as the primary planning sources of truth:

1. `docs/project-overview.md`
2. `docs/environment-requirements.md`
3. `docs/architecture/overview.md`
4. `docs/roadmap.md`
5. `docs/wbs.md`
6. `docs/issues/`
7. `docs/decisions/`
8. `docs/policies/`
9. `AGENTS.md`

## Repository Guide
- `AGENTS.md`: agent working rules and update requirements
- `docs/project-overview.md`: problem statement, goals, scope, constraints
- `docs/operating-model.md`: how humans and agents should collaborate
- `docs/environment-requirements.md`: centralized environment inventory and readiness tracking
- `docs/environment-bootstrap.md`: current project-local startup guidance for Phase 1 environments
- `docs/roadmap.md`: current project roadmap
- `docs/wbs.md`: current work breakdown structure
- `docs/issues/`: active issue dashboard, archive, and supporting issue notes
- `docs/architecture/`: system boundaries, context, task lifecycle
- `docs/decisions/`: architecture decisions
- `docs/decisions/decision-backlog.md`: decision dashboard for pending and recently selected choices
- `docs/issues/issue-dashboard.md`: issue dashboard for active near-term project issues and blockers
- `docs/policies/`: intake, issue-management, and change-control rules
- `docs/templates/`: formatting templates for AI-maintained planning docs
- `prompts/init-project.prompt.md`: initialization prompt for Codex or similar agents

## Working Principle
This repo should evolve in this order:
1. clarify scope
2. define architecture boundaries
3. define roadmap and WBS
4. define policies and operating model
5. implement the smallest closed loop
6. expand carefully

## Near-Term Objective
The first practical milestone is a **minimum closed loop**:
- an issue or comment can create a normalized task request
- an agent session can be started in an isolated runtime
- the agent can propose a code change via branch/PR
- CI validates the change independently
- a human remains the merge control point

## Non-Goals for Initialization
This initialization package does **not** assume:
- a fixed forge vendor
- a fixed agent product
- a fixed CI/CD stack
- direct agent control over production deployment
- that prompts alone are sufficient as long-term system memory

## How to Use This Baseline
1. Read `docs/project-overview.md`
2. Read `docs/architecture/overview.md`
3. Read `docs/roadmap.md` and `docs/wbs.md`
4. Read `AGENTS.md`
5. Use `prompts/init-project.prompt.md` to initialize future agent runs
6. Review `docs/issues/issue-dashboard.md` for active near-term project issues
7. Read any supporting note linked from an active dashboard item under `docs/issues/items/`
8. Review `docs/decisions/decision-backlog.md` for pending and recently selected decisions
9. Update roadmap/WBS and issue/decision docs through their templates when scope changes

## Project-Local Dev Startup
Phase 1 environment dependencies do not all need to be bundled inside the repository, but the current operator surface should still be startable from project-owned entrypoints.

Current bootstrap commands:

```powershell
powershell -File scripts/dev/manage-dev-environment.ps1 -Command init
powershell -File scripts/dev/manage-dev-environment.ps1 -Command up
powershell -File scripts/dev/manage-dev-environment.ps1 -Command up -GiteaDatabaseMode sqlite
powershell -File scripts/dev/manage-dev-environment.ps1 -Command up -SkipGitea
powershell -File scripts/dev/manage-dev-environment.ps1 -Command status
npm run dev:env:init
npm run dev:env:up
npm run dev:env:up:sqlite
npm run dev:env:up:no-gitea
npm run dev:env:status
npm run dev:env:down
```

`dev:env:up` now also starts the default task-intake and review-follow-up webhook listeners from repo-owned config, and the default local Gitea repo bootstrap path now ensures both issue-comment and review-follow-up webhooks are configured against that repo.

Current platform package commands:

```powershell
npm install
npm run validate:platform
npm run typecheck
npm run task-gateway:webhook
npm run review-surface:webhook
npm run dev:gitea-repo -- ensure-local-repo --owner howard --repo agent-sdlc --seed-from .
npm run dev:gitea-runner -- ensure-runner
npm run proposal-surface -- create-gitea-pr --session .agent-sdlc/state/agent-sessions/<agent_session_id>.json
docker build -f docker/worker-runtime/Dockerfile -t agent-sdlc-worker-runtime:test .
```

When `--seed-from .` is used, the local Gitea repo is seeded from the source repo's current `HEAD` into remote `main` so the local forge sees the same tracked workflow and platform files as the active workspace.
If the local forge does not auto-create Actions runs for fresh PR events, the tracked workflow also supports `workflow_dispatch` so maintainers can manually dispatch `phase1-ci` against the proposal branch while the local trigger gap is being investigated.

The default local ports come from `config/dev/gitea-bootstrap.json` and are intentionally forwarded to higher, non-common host ports.

See `docs/environment-bootstrap.md` for the current bootstrap posture and what each command covers.
