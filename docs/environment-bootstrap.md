# Environment Bootstrap

## Purpose
This document defines the current Phase 1 bootstrap posture for environments that support the minimum closed loop.

It complements `docs/environment-requirements.md` by describing how maintainers can bring up the current development stack from repository-owned entrypoints without forcing every dependency to be packaged inside the repository on day one.

## Current Bootstrap Posture
- prefer repository-local commands as the operator-facing startup surface
- allow backing services to remain external or tool-managed when that keeps Phase 1 replaceable and light
- keep concrete local startup settings in a repo-owned config file rather than only in ad hoc local commands
- use explicit host-port forwarding on non-common ports so local startup stays conflict-resistant and easier to translate into `docker compose` or Kubernetes manifests later
- keep bootstrap entrypoints stable even if the underlying implementation later moves to `docker compose` or another one-command launcher
- defer a full single-file orchestration package until the active service mix is stable enough to justify it
- converge the platform's growing control-plane logic toward the selected `TypeScript` / `Node.js LTS` / `npm` stack while allowing temporary bootstrap wrappers to stay in PowerShell

## Current Bootstrap Surfaces
| Environment ID | Current Bootstrap Path | Current Posture |
|---|---|---|
| ENV-001 | `scripts/dev/manage-dev-environment.ps1 -Command up` | Starts a local Gitea development stack from repo-owned config. The default local path uses PostgreSQL-backed Gitea, explicit high-port forwarding, and non-interactive installation with an admin user bootstrap. |
| ENV-002 | `npm install`; `npm run validate:platform`; `node scripts/task-gateway.js ...`; `node scripts/agent-control.js ...` | Prepares the npm-managed control-plane baseline and file-backed task/session records from repo-local CLI entrypoints. The current slice supports file-based Gitea issue-comment normalization and direct session-start placeholders, while webhook delivery and runtime handoff remain pending under WBS `3.1` and `3.2`. |
| ENV-003 | `docker build -f docker/worker-runtime/Dockerfile ...` | Builds the first repo-owned worker-runtime image scaffold on top of the host-local Docker-compatible runner. Runtime handoff and session workspace launch remain pending under WBS `3.3`. |
| ENV-004 | Not bootstrapped locally yet | CI stays an independent verifier and will be attached after the PR path exists. |
| ENV-005 | `scripts/dev/manage-dev-environment.ps1 -Command init` | Creates the `.agent-sdlc/state/` and `.agent-sdlc/traceability/` surfaces used by the first implementation slice. |
| ENV-006 | Operator-provided environment variables or secret injection | Secrets remain scoped and profile-specific; no broad bootstrap helper is introduced yet. |

## Current Commands
Run these commands from the repository root in PowerShell:

```powershell
powershell -File scripts/dev/manage-dev-environment.ps1 -Command init
powershell -File scripts/dev/manage-dev-environment.ps1 -Command up
powershell -File scripts/dev/manage-dev-environment.ps1 -Command up -GiteaDatabaseMode sqlite
powershell -File scripts/dev/manage-dev-environment.ps1 -Command up -SkipGitea
powershell -File scripts/dev/manage-dev-environment.ps1 -Command status
powershell -File scripts/dev/manage-dev-environment.ps1 -Command down
npm install
npm run validate:platform
npm run typecheck
node scripts/task-gateway.js normalize-gitea-issue-comment --event docs/examples/gitea-issue-comment-event.example.json
node scripts/agent-control.js start-session --task-request .agent-sdlc/state/task-requests/<task_request_id>.json
docker build -f docker/worker-runtime/Dockerfile -t agent-sdlc-worker-runtime:test .
```

Command behavior:
- `init` creates the local `.agent-sdlc/` state and development-environment directories used by the first implementation slice
- `up` runs `init`, then starts the local PostgreSQL-backed Gitea development stack, applies the tracked bootstrap settings, and completes the initial install path non-interactively if Docker is available
- `up -GiteaDatabaseMode sqlite` starts the lighter single-container Gitea fallback instead of the PostgreSQL-backed stack
- `up -SkipGitea` prepares the project-local state surfaces without requiring the local forge container to be available yet
- `status` reports the current project-local bootstrap state without changing it
- `down` stops and removes the local Gitea development stack but leaves state directories intact
- `npm install` installs the selected npm-managed control-plane baseline for platform code
- `npm run validate:platform` performs syntax validation for the current platform CLI scaffolds
- `npm run typecheck` runs the selected TypeScript baseline in no-emit mode across the current platform package
- `node scripts/task-gateway.js normalize-gitea-issue-comment --event <path>` normalizes one file-backed Gitea issue-comment event into `.agent-sdlc/state/task-requests/<task_request_id>.json`
- `node scripts/agent-control.js start-session --task-request <path>` creates `.agent-sdlc/state/agent-sessions/<agent_session_id>.json` for an auto-approved task request and returns the pending session metadata
- `docker build -f docker/worker-runtime/Dockerfile -t agent-sdlc-worker-runtime:test .` builds the first worker-runtime image scaffold defined in the repository

## Repo-Owned Bootstrap Inputs
The current local forge bootstrap and platform packaging baseline are configured by:
- `config/dev/gitea-bootstrap.json`
- `package.json`
- `package-lock.json`
- `tsconfig.json`
- `docker/worker-runtime/Dockerfile`
- `.dockerignore`

The local forge bootstrap config currently owns:
- the Docker Desktop path used for auto-start attempts
- the explicit forwarded host ports and bind address
- the default Gitea database mode
- the default local Gitea app settings
- the local bootstrap admin user values for the dev stack

The package and runtime files currently own:
- the selected npm-managed platform package baseline
- the TypeScript no-emit validation baseline for platform code
- the first repo-owned worker-runtime image definition

## Configuration Knobs
The current bootstrap script supports these optional environment variables:
- `AGENT_SDLC_DOCKER_DESKTOP_PATH`
- `AGENT_SDLC_DOCKER_START_TIMEOUT_SECONDS`
- `AGENT_SDLC_GITEA_IMAGE`
- `AGENT_SDLC_GITEA_HTTP_PORT`
- `AGENT_SDLC_GITEA_SSH_PORT`
- `AGENT_SDLC_GITEA_DB_MODE`
- `AGENT_SDLC_GITEA_POSTGRES_IMAGE`
- `AGENT_SDLC_GITEA_POSTGRES_PORT`
- `AGENT_SDLC_GITEA_POSTGRES_DB`
- `AGENT_SDLC_GITEA_POSTGRES_USER`
- `AGENT_SDLC_GITEA_POSTGRES_PASSWORD`

## Why PostgreSQL Is The Default Local Path
Gitea does not strictly require PostgreSQL for a local development bootstrap. SQLite is still a valid lighter-weight option for a narrow single-container bring-up.

The local bootstrap now defaults to PostgreSQL because:
- it matches a more realistic multi-service forge setup
- it makes later consolidation into `docker compose` or another one-command launcher more natural
- it flushes out database and service-start ordering earlier instead of hiding them until later

## Automated Initialization Scope
The bootstrap script now covers:
- starting Docker Desktop from the tracked default path when needed
- creating the local PostgreSQL service when the selected mode is `postgres`
- starting Gitea with tracked install settings and `INSTALL_LOCK`
- generating local Gitea secrets for the dev stack
- ensuring the tracked admin user exists after startup
- reapplying the tracked `mustChangePassword` setting when the bootstrap refreshes the admin password so manual sign-in stays stable across restarts

## Remaining Initialization Tasks
Starting the containers is no longer the only bootstrap step, but several workflow-specific initialization tasks still remain:
- create an API token for later branch, PR, or webhook automation
- create the dev repository and enable issue / PR usage
- replace the current file-based task gateway input with actual webhook delivery and adapter wiring
- replace the current pending-only session starter placeholder with runtime handoff into the worker scaffold
- add webhook and branch-protection setup when the task gateway and PR path are implemented
- attach CI or runner integration later during WBS `3.5`

## Known Local Friction Points
- the rootless Gitea image expects writable data and config mounts; if host-mounted directories behave badly on Windows, switch the service data to named Docker volumes before spending time on deeper debugging
- the first PostgreSQL bring-up can take noticeably longer than a normal restart because the database has to initialize before Gitea can connect
- the stack only covers forge and state scaffolding right now; webhook registration, automation users, runner wiring, and CI protection are still later-slice work
- if an older local data set was created before this bootstrap synced the admin `mustChangePassword` flag during password refresh, run `powershell -File scripts/dev/manage-dev-environment.ps1 -Command up` once to reconcile the existing admin account with the tracked bootstrap setting

## Non-Goals
- fully provisioning every environment dependency from scratch
- replacing future CI or deploy ownership with local bootstrap scripts
- forcing the Phase 1 stack into `docker compose` before the working service mix is clear

## Expected Evolution
- Keep using repository-local bootstrap entrypoints as the stable operator surface.
- Expand the script or replace its internals as WBS `3.1` through `3.5` land.
- Re-evaluate whether `docker compose` or an equivalent one-command launcher is the right consolidation step once the actual service topology is no longer speculative.
- Treat the current Node.js control-host CLIs as the first slice on the selected platform stack, then move them under npm and TypeScript as the control plane grows.
- Add repo-owned Dockerfiles for the control-plane and worker runtime before consolidating them into a repo-owned compose package.
