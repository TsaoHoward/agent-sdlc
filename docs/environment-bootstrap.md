# Environment Bootstrap

## Purpose
This document defines the current Phase 1 bootstrap posture for environments that support the minimum closed loop.

It complements `docs/environment-requirements.md` by describing how maintainers can bring up the current development stack from repository-owned entrypoints without forcing every dependency to be packaged inside the repository on day one.

## Current Bootstrap Posture
- prefer repository-local commands as the operator-facing startup surface
- allow backing services to remain external or tool-managed when that keeps Phase 1 replaceable and light
- keep concrete local startup settings in a repo-owned template plus ignored local config rather than only in ad hoc local commands
- use explicit host-port forwarding on non-common ports so local startup stays conflict-resistant and easier to translate into `docker compose` or Kubernetes manifests later
- keep bootstrap entrypoints stable even if the underlying implementation later moves to `docker compose` or another one-command launcher
- defer a full single-file orchestration package until the active service mix is stable enough to justify it
- converge the platform's growing control-plane logic toward the selected `TypeScript` / `Node.js LTS` / `npm` stack while allowing temporary bootstrap wrappers to stay in PowerShell

## Current Bootstrap Surfaces
| Environment ID | Current Bootstrap Path | Current Posture |
|---|---|---|
| ENV-001 | `scripts/dev/manage-dev-environment.ps1 -Command up`; `npm run dev:env:up`; `npm run dev:gitea-repo -- ensure-local-repo ...` | Starts a local Gitea development stack from repo-owned template/local config and now has a repo-local helper to provision the default local owner/repository path for proposal-flow testing. The default local path uses PostgreSQL-backed Gitea, explicit high-port forwarding, non-interactive installation with an admin user bootstrap, a repo-owned webhook allowed-host list for host callbacks, and repo-hook configuration for both issue-comment intake and review-follow-up sync. |
| ENV-002 | `npm install`; `npm run validate:platform`; `npm run task-gateway:webhook`; `node scripts/agent-control.js ...`; `node scripts/proposal-surface.js ...`; `node scripts/review-surface.js ...`; `npm run review-surface:webhook`; `scripts/dev/manage-dev-environment.ps1 -Command up -SkipGitea` | Prepares the npm-managed control-plane baseline and exposes repo-local webhook, session-start, proposal-surface, and review-surface CLIs. The current slice supports actual Gitea issue-comment webhook delivery, source-event retention, normalized task-request persistence, direct handoff into the worker runtime scaffold, PR creation against the local Gitea forge, explicit review-outcome synchronization back into durable traceability records, and bootstrap-managed task/review webhook listeners for the default local repo posture. |
| ENV-003 | `docker build -f docker/worker-runtime/Dockerfile ...`; `node scripts/agent-control.js ...` | Builds and exercises the first repo-owned worker-runtime image scaffold on top of the host-local Docker-compatible runner. The current runtime handoff launches a per-session container, prepares a fresh workspace checkout from the forge target repository and branch, and exports runtime launch artifacts under `.agent-sdlc/runtime/`. |
| ENV-004 | `npm run dev:gitea-runner -- ensure-runner`; `.gitea/workflows/phase1-ci.yml` | Boots a local Gitea Actions runner and executes the first PR-triggered CI workflow. The current skeleton collects verification metadata into `.agent-sdlc/ci/verification-metadata.json`, emits it in job logs and step summaries, attaches CI run references and final verification status to the traceability artifact, refreshes the PR traceability block for reviewers, and uploads those artifacts as persisted workflow outputs even when the local forge root URL is localhost-backed. The tracked workflow also supports `workflow_dispatch` as an operator fallback for targeted reruns or local debugging. |
| ENV-005 | `scripts/dev/manage-dev-environment.ps1 -Command init` | Creates the `.agent-sdlc/state/` and `.agent-sdlc/traceability/` surfaces used by the first implementation slice. |
| ENV-006 | Operator-provided environment variables or secret injection | Secrets remain scoped and profile-specific; no broad bootstrap helper is introduced yet. |

## Current Commands
Run these commands from the repository root in PowerShell:

```powershell
npm run dev:gitea-bootstrap-config
powershell -File scripts/dev/manage-dev-environment.ps1 -Command init
powershell -File scripts/dev/manage-dev-environment.ps1 -Command up
powershell -File scripts/dev/manage-dev-environment.ps1 -Command up -GiteaDatabaseMode sqlite
powershell -File scripts/dev/manage-dev-environment.ps1 -Command up -SkipGitea
powershell -File scripts/dev/manage-dev-environment.ps1 -Command status
powershell -File scripts/dev/manage-dev-environment.ps1 -Command down
npm run dev:env:init
npm run dev:env:up
npm run dev:env:up:sqlite
npm run dev:env:up:no-gitea
npm run dev:env:status
npm run dev:env:down
npm install
npm run validate:platform
npm run typecheck
npm run task-gateway:webhook
npm run review-surface:webhook
npm run dev:gitea-bootstrap-config
npm run dev:gitea-repo -- ensure-local-repo --owner howard --repo agent-sdlc --seed-from .
npm run dev:gitea-runner -- ensure-runner
node scripts/task-gateway.js normalize-gitea-issue-comment --event docs/examples/gitea-issue-comment-event.example.json
node scripts/agent-control.js start-session --task-request .agent-sdlc/state/task-requests/<task_request_id>.json
node scripts/proposal-surface.js create-gitea-pr --session .agent-sdlc/state/agent-sessions/<agent_session_id>.json
node scripts/review-surface.js sync-gitea-pr-review-outcome --session .agent-sdlc/state/agent-sessions/<agent_session_id>.json
node scripts/review-surface.js sync-gitea-pr-review-outcome --proposal gitea:<host>/<owner>/<repo>#pull/<index>
node scripts/review-surface.js sync-gitea-pr-review-event --event docs/examples/gitea-pull-request-review-event.example.json
node scripts/task-gateway.js serve-configured-gitea-webhook
node scripts/review-surface.js serve-configured-gitea-review-webhook
docker build -f docker/worker-runtime/Dockerfile -t agent-sdlc-worker-runtime:test .
```

Command behavior:
- `npm run dev:gitea-bootstrap-config` generates ignored local config at `config/dev/gitea-bootstrap.json` from the tracked `config/dev/gitea-bootstrap.template.json`
- `init` creates the local `.agent-sdlc/` state and development-environment directories used by the first implementation slice
- `up` runs `init`, then starts the local PostgreSQL-backed Gitea development stack, applies the local bootstrap config when present or the tracked template otherwise, and completes the initial install path non-interactively if Docker is available
- `up` now also starts the managed task-gateway and review-follow-up webhook listeners from the template/local bootstrap config, then ensures the default local Gitea repo plus its webhook set when local forge bootstrap is enabled
- `up -GiteaDatabaseMode sqlite` starts the lighter single-container Gitea fallback instead of the PostgreSQL-backed stack
- `up -SkipGitea` prepares the project-local state surfaces and managed control-host webhook listeners without requiring the local forge container to be available yet
- `status` reports the current project-local bootstrap state without changing it
- `down` stops the managed control-host webhook listeners, stops and removes the local Gitea development stack when present, and leaves state directories intact
- `npm run dev:env:*` exposes the same repo-owned local bootstrap entrypoints through the npm command surface so local Gitea startup is discoverable alongside the other Phase 1 operator commands
- `npm install` installs the selected npm-managed control-plane baseline for platform code
- `npm run validate:platform` performs syntax validation for the current platform CLI scaffolds
- `npm run typecheck` runs the selected TypeScript baseline in no-emit mode across the current platform package
- `npm run task-gateway:webhook` starts the Phase 1 webhook listener from the template/local bootstrap config; the default is `http://127.0.0.1:4010/hooks/gitea/issue-comment`
- `npm run review-surface:webhook` starts the Phase 1 review-follow-up listener from the template/local bootstrap config; the default is `http://127.0.0.1:4011/hooks/gitea/pull-request-review`
- `npm run dev:gitea-repo -- ensure-local-repo --owner <owner> --repo <repo> --seed-from <path>` provisions a local Gitea owner/repository path and can seed its `main` branch from the local repository
- `npm run dev:gitea-runner -- ensure-runner` provisions or refreshes the local Gitea Actions runner container and adapts the runner/job-container network topology when the tracked local forge base URL points at host loopback
- `node scripts/task-gateway.js normalize-gitea-issue-comment --event <path>` normalizes one file-backed Gitea issue-comment event into `.agent-sdlc/state/task-requests/<task_request_id>.json`
- `node scripts/agent-control.js start-session --task-request <path>` creates `.agent-sdlc/state/agent-sessions/<agent_session_id>.json`, launches the worker-runtime container, and prepares a session-local workspace plus runtime artifacts under `.agent-sdlc/runtime/`
- `node scripts/proposal-surface.js create-gitea-pr --session <path>` creates or updates the Phase 1 proposal branch and Gitea PR while force-adding the linked traceability artifact into the prepared workspace
- `node scripts/review-surface.js sync-gitea-pr-review-outcome --session <path>` reads the linked Gitea PR review state, updates the canonical root traceability artifact plus all matching session-local traceability copies for the same proposal, and refreshes the PR traceability block with explicit review decision metadata
- `node scripts/review-surface.js sync-gitea-pr-review-outcome --proposal <proposal_ref>` resolves the latest matching session set from a known Gitea PR reference and performs the same review-outcome sync without requiring a specific session path
- `node scripts/review-surface.js sync-gitea-pr-review-event --event <path>` accepts a file-backed Gitea `pull_request_review` or review-relevant `pull_request` event, resolves the linked proposal, and syncs the durable review outcome for that PR
- `node scripts/task-gateway.js serve-configured-gitea-webhook` exposes the configured issue-comment intake path over HTTP
- `node scripts/review-surface.js serve-configured-gitea-review-webhook` exposes the configured review-event sync path over HTTP so local Gitea review or PR-close events can drive traceability refresh without a manual command hop
- `docker build -f docker/worker-runtime/Dockerfile -t agent-sdlc-worker-runtime:test .` builds the first worker-runtime image scaffold defined in the repository

Seed behavior:
- `npm run dev:gitea-repo -- ensure-local-repo --owner <owner> --repo <repo> --seed-from <path>` now force-pushes the source repo's current `HEAD` into the local Gitea repo's `main` branch so local PR and CI testing use the same tracked workflow files as the active workspace
- the same repo helper now also ensures the tracked issue-comment and review-follow-up webhook set points at the configured control-host callback URLs

Local CI fallback:
- `.gitea/workflows/phase1-ci.yml` supports `workflow_dispatch` so maintainers can manually dispatch the tracked workflow against a proposal branch for targeted reruns or local debugging

## Repo-Owned Bootstrap Inputs
The current local forge bootstrap and platform packaging baseline are configured by:
- `config/dev/gitea-bootstrap.template.json`
- `config/dev/gitea-bootstrap.json` when generated locally; this file is ignored by Git
- `package.json`
- `package-lock.json`
- `tsconfig.json`
- `docker/worker-runtime/Dockerfile`
- `.dockerignore`

The local forge bootstrap template/local config currently owns:
- the Docker Desktop path used for auto-start attempts
- the explicit forwarded host ports and bind address
- the default Gitea database mode
- the default local Gitea app settings
- the local Gitea webhook allowed-host list needed for host callback delivery from the forge container
- the local bootstrap admin user values for the dev stack
- the default local owner/repo bootstrap target
- the callback host plus route/port settings for the task-intake and review-follow-up webhook paths

Config resolution follows ADR-0008:
- local config: `config/dev/gitea-bootstrap.json`
- template config: `config/dev/gitea-bootstrap.template.json`
- generator: `npm run dev:gitea-bootstrap-config`

The package and runtime files currently own:
- the selected npm-managed platform package baseline
- the TypeScript no-emit validation baseline for platform code
- the first webhook-listener command surface for Gitea issue-comment delivery, with npm startup settings resolved from template/local config
- the first review-follow-up webhook command surface for Gitea PR review and close events, with npm startup settings resolved from template/local config
- the local Gitea Actions runner helper and first PR-triggered CI workflow skeleton
- the first repo-owned worker-runtime image definition
- the current per-session runtime-launch behavior and exported runtime-launch artifacts
- the first branch/PR proposal command surface, review-follow-up sync surface, and traceability-artifact writer

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
- `AGENT_SDLC_WORKER_IMAGE`
- `AGENT_SDLC_GITEA_BASE_URL`
- `AGENT_SDLC_GITEA_USERNAME`
- `AGENT_SDLC_GITEA_PASSWORD`
- `AGENT_SDLC_GITEA_TOKEN`
- `AGENT_SDLC_GITEA_CONTAINER`
- `AGENT_SDLC_GITEA_RUNNER_CONTAINER`
- `AGENT_SDLC_GITEA_RUNNER_IMAGE`
- `AGENT_SDLC_GITEA_RUNNER_NAME`
- `AGENT_SDLC_GITEA_RUNNER_LABELS`
- `AGENT_SDLC_GITEA_RUNNER_NETWORK`
- `AGENT_SDLC_GITEA_RUNNER_INSTANCE_URL`

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
- starting the managed task-intake and review-follow-up webhook listeners for the default control-host posture
- ensuring the default local Gitea owner/repo path exists when configured
- ensuring the default issue-comment and review-follow-up webhook set exists on that local repo
- reapplying the tracked `mustChangePassword` setting when the bootstrap refreshes the admin password so manual sign-in stays stable across restarts

## Remaining Initialization Tasks
Starting the containers is no longer the only bootstrap step, but several workflow-specific initialization tasks still remain:
- create an API token for later branch, PR, or webhook automation
- add webhook and branch-protection setup when the task gateway and PR path are implemented
- validate the default bootstrap path from live issue-comment intake through proposal/CI/review without manual normalization or replay steps
- investigate local Gitea artifact listing visibility if operator-facing browsing of stored workflow artifacts becomes a near-term need

## Known Local Friction Points
- the rootless Gitea image expects writable data and config mounts; if host-mounted directories behave badly on Windows, switch the service data to named Docker volumes before spending time on deeper debugging
- the first PostgreSQL bring-up can take noticeably longer than a normal restart because the database has to initialize before Gitea can connect
- under the localhost-rooted local forge topology, the runner helper now shifts runner and job containers onto host networking and injects an `agent-sdlc-gitea` host alias so checkout and artifact upload both succeed; during validation, local Gitea still returned an empty artifact listing response even though uploaded chunks were persisted on disk
- local Gitea host callbacks require a non-default webhook allowlist because `host.docker.internal` resolves to a private address from inside the forge container; the bootstrap now sets `webhook.ALLOWED_HOST_LIST=external,private` so the default issue-comment and review listeners are reachable
- if an older local data set was created before this bootstrap synced the admin `mustChangePassword` flag during password refresh, run `powershell -File scripts/dev/manage-dev-environment.ps1 -Command up` once to reconcile the existing admin account with the template/local bootstrap setting

## Non-Goals
- fully provisioning every environment dependency from scratch
- replacing future CI or deploy ownership with local bootstrap scripts
- forcing the Phase 1 stack into `docker compose` before the working service mix is clear

## Expected Evolution
- Keep using repository-local bootstrap entrypoints as the stable operator surface.
- Expand the script or replace its internals as WBS `3.1` through `3.6` land.
- Re-evaluate whether `docker compose` or an equivalent one-command launcher is the right consolidation step once the actual service topology is no longer speculative.
- Treat the current Node.js control-host CLIs as the first slice on the selected platform stack, then move them under npm and TypeScript as the control plane grows.
- Add repo-owned Dockerfiles for the control-plane and worker runtime before consolidating them into a repo-owned compose package.

## Change Log
- 2026-04-15: Initial version.
- 2026-04-15: Recorded the repo-owned bootstrap config, npm baseline, and worker-runtime Dockerfile scaffold.
- 2026-04-15: Updated the control-host and worker-runtime bootstrap posture after landing webhook intake, source-event retention, and per-session runtime handoff.
- 2026-04-16: Updated the bootstrap posture after landing the local Gitea repo helper, proposal-surface CLI, and first PR-linked traceability artifact.
- 2026-04-16: Added the local Gitea Actions runner helper and recorded the first PR-triggered CI verification skeleton.
- 2026-04-16: Updated the local runner bootstrap notes after validating successful localhost-topology artifact upload in local Gitea run `#19`.
- 2026-04-20: Updated the bootstrap posture after landing review-outcome synchronization and promoting `review-surface` to the repo-owned operator command set.
- 2026-04-21: Updated the bootstrap posture after adding review-event replay and webhook entrypoints so Gitea review/close events can drive traceability refresh without a session-specific manual command.
- 2026-04-21: Updated the bootstrap posture after wiring the default local repo webhook set and managed control-host listeners into the repo-owned local startup path.
- 2026-04-21: Updated the bootstrap posture after confirming that local Gitea host callbacks need `webhook.ALLOWED_HOST_LIST=external,private`, then validating live PR close/reopen delivery into the bootstrap-managed review listener.
