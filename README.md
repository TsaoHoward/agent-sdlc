# Agent-First SDLC Bootstrap

## Purpose
This repository is the initialization baseline for an agent-oriented SDLC system.

The target user experience is:

`issue -> task intake -> agent session -> code change -> branch/PR -> CI verification -> human review/merge`

The target architecture is deliberately layered so the system can evolve without being locked to a single forge, agent runtime, CI stack, or deployment mechanism.

## Current Status
This repository is in **project-baseline** state.

The current goal is **not** to deliver the full platform immediately. The goal is to establish:
- a stable planning baseline
- architecture boundaries
- decision and issue records
- roadmap and WBS structure
- human/agent operating rules
- initialization prompt(s) for future agent runs

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
```

The default local ports come from `config/dev/gitea-bootstrap.json` and are intentionally forwarded to higher, non-common host ports.

See `docs/environment-bootstrap.md` for the current bootstrap posture and what each command covers.
