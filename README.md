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
- a repo-owned testing workflow baseline with local CLI and GUI procedures plus an active test dashboard

The goal is still **not** to deliver the full platform immediately. The current focus is to harden the smallest useful issue-driven experience without collapsing architecture boundaries.
The current local `howard/agent-sdlc` seeded repo path should now be treated as a **platform workbench / internal-eval baseline**, not as sufficient evidence that the service is ready for broader pilot or production use on non-platform repositories.
The first valid external-target service-evaluation evidence now exists on `eval/target-docs`: issue `#3` / comment `#153` -> task `trq-f77d70ed7f92` -> session `ags-7f12724630cc` -> PR `#4` -> CI run `#56` (`success`).

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
- improve operator-facing artifact browsing or listing now that traceability, CI metadata, and review sync are in place
- keep `docs/user-capability-matrix.md` aligned with the actual supported `@agent` surfaces, task tokens, and lifecycle boundaries
- expand beyond the first `target-docs` external-target baseline only when a second fixture family (`code` or `ci`) is worth the extra coordination cost
- keep explicit service-state labeling (`Workbench`, `Internal Eval`, `Pilot`, `Production`) and promotion rules aligned with real evidence
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
8. `docs/testing/`
9. `docs/user-capability-matrix.md`
10. `docs/policies/`
11. `AGENTS.md`

## Repository Guide
- `AGENTS.md`: agent working rules and update requirements
- `docs/project-overview.md`: problem statement, goals, scope, constraints
- `docs/user-capability-matrix.md`: current supported user-facing `@agent` surfaces, task tokens, and lifecycle coverage
- `docs/operating-model.md`: how humans and agents should collaborate
- `docs/environment-requirements.md`: centralized environment inventory and readiness tracking
- `docs/environment-bootstrap.md`: current project-local startup guidance for Phase 1 environments
- `docs/roadmap.md`: current project roadmap
- `docs/wbs.md`: current work breakdown structure
- `docs/issues/`: active issue dashboard, archive, and supporting issue notes
- `docs/testing/`: testing workflow index, test plan, framework, local procedures, active dashboard, archive, and canonical test procedures
- `docs/architecture/`: system boundaries, context, task lifecycle
- `docs/decisions/`: architecture decisions
- `docs/decisions/decision-backlog.md`: decision dashboard for pending and recently selected choices
- `docs/issues/issue-dashboard.md`: issue dashboard for active near-term project issues and blockers
- `docs/policies/`: intake, issue-management, and change-control rules
- `docs/policies/branch-and-local-forge-sync.md`: proposal-branch and local-forge synchronization rule for Phase 1 local validation
- `docs/policies/configuration-management.md`: repository-wide config template and local-config policy
- `docs/policies/service-state-and-evaluation.md`: service-state labels plus the rule that platform self-test evidence is distinct from broader external target-repo service evaluation
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
8. Read `docs/testing/README.md` as the entrypoint to the local testing workflow
9. Review `docs/testing/test-dashboard.md` for active near-term validation work and any referenced canonical test case under `docs/testing/items/`
10. Review `docs/decisions/decision-backlog.md` for pending and recently selected decisions
11. Update roadmap/WBS plus issue/testing/decision docs through their templates when scope changes

## Project-Local Dev Startup
Phase 1 environment dependencies do not all need to be bundled inside the repository, but the current operator surface should still be startable from project-owned entrypoints.

Current bootstrap commands:

```powershell
npm run dev:gitea-bootstrap-config
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

`dev:env:up` now also starts the default task-intake and review-follow-up webhook listeners from template/local config, and the default local Gitea repo bootstrap path now ensures both issue-comment and review-follow-up webhooks are configured against that repo.
The npm `dev:env:init` and `dev:env:up*` commands ensure the ignored local Gitea bootstrap config before starting; run `npm run dev:gitea-bootstrap-config` once first when using the direct PowerShell `up` command without password environment variables.

Current platform package commands:

```powershell
npm install
npm run validate:platform
npm run typecheck
npm run task-gateway:webhook
npm run review-surface:webhook
npm run dev:gitea-bootstrap-config
npm run dev:agent-execution-config
npm run dev:gitea-repo -- ensure-local-repo --owner howard --repo agent-sdlc --seed-from .
npm run dev:gitea-runner -- ensure-runner
npm run proposal-surface -- create-gitea-pr --session .agent-sdlc/state/agent-sessions/<agent_session_id>.json
docker build -f docker/worker-runtime/Dockerfile -t agent-sdlc-worker-runtime:test .
```

When `--seed-from .` is used, the local Gitea repo is seeded from the source repo's current `HEAD` into remote `main` so the local forge sees the same tracked workflow and platform files as the active workspace.
For the default local seeded-repo workflow, reseed local forge `main` before proposal or CI validation whenever the workspace commit under test has not yet been pushed into the local forge; the formal rule now lives in `docs/policies/branch-and-local-forge-sync.md`.
If a local regression ever prevents auto-created Actions runs for fresh PR events, the tracked workflow also supports `workflow_dispatch` so maintainers can manually dispatch `phase1-ci` against the proposal branch during troubleshooting.

The default local ports come from the tracked `config/dev/gitea-bootstrap.template.json`. Operators can generate an ignored local override at `config/dev/gitea-bootstrap.json` with `npm run dev:gitea-bootstrap-config`; loaders prefer that local file when present and otherwise fall back to the template.

See `docs/environment-bootstrap.md` for the current bootstrap posture and what each command covers, then use `docs/testing/README.md` and `docs/testing/local-test-procedures.md` for the repeatable operator test flow.
